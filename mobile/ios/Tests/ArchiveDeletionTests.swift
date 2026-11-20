import XCTest
@testable import TideEnglishCore

final class ArchiveDeletionTests: XCTestCase {
    func testRecoveryBackupsRollbackAndDeleteWithArchive() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("recovery-backups")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let backup = dir.appendingPathComponent("original.json"), data = Data("original".utf8)
        try data.write(to: backup)
        let files = ArchiveDeletionTransaction.learningFiles(in: root), staging = root.appendingPathComponent("pending-deletions")
        XCTAssertThrowsError(try ArchiveDeletionTransaction.run(files: files, stagingRoot: staging) {
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertEqual(try Data(contentsOf: backup), data)
        try ArchiveDeletionTransaction.run(files: files, stagingRoot: staging) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testStageAndCommitFailuresRestoreBothFiles() throws {
        for failure in ["stage", "commit"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let first = root.appendingPathComponent("backup"), second = root.appendingPathComponent("cache")
            try Data("backup".utf8).write(to: first); try Data("cache".utf8).write(to: second)
            var moves = 0
            XCTAssertThrowsError(try ArchiveDeletionTransaction.run(files: [first, second], stagingRoot: root.appendingPathComponent("staging"), move: { from, to in
                moves += 1
                if failure == "stage" && moves == 2 { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: from, to: to)
            }, commit: { if failure == "commit" { throw CocoaError(.fileWriteOutOfSpace) } }))
            XCTAssertEqual(try Data(contentsOf: first), Data("backup".utf8))
            XCTAssertEqual(try Data(contentsOf: second), Data("cache".utf8))
        }
    }
    func testRollbackFailureIsReportedAndCanBeRetried() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("backup"), second = root.appendingPathComponent("cache"), staging = root.appendingPathComponent("staging")
        try Data("backup".utf8).write(to: first); try Data("cache".utf8).write(to: second)
        var moves = 0
        XCTAssertThrowsError(try ArchiveDeletionTransaction.run(files: [first, second], stagingRoot: staging, move: { from, to in
            moves += 1
            if moves == 2 || moves == 3 { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: from, to: to)
        }, commit: {})) { XCTAssertEqual($0 as? ArchiveDeletionTransaction.Failure, .rollbackFailed) }
        XCTAssertThrowsError(try ArchiveDeletionTransaction.run(files: [first, second], stagingRoot: staging, commit: { throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try Data(contentsOf: first), Data("backup".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("cache".utf8))
    }
    func testRollbackFailureThenRestartRestoresBeforeNormalWriteAndDeletion() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let first = root.appendingPathComponent("backup"), second = root.appendingPathComponent("cache"), staging = root.appendingPathComponent("staging")
        try Data("backup".utf8).write(to: first); try Data("old".utf8).write(to: second)
        var moves = 0
        XCTAssertThrowsError(try ArchiveDeletionTransaction.run(files: [second, first], stagingRoot: staging, move: { from, to in
            moves += 1
            if moves == 2 || moves == 3 { throw CocoaError(.fileWriteNoPermission) }
            try manager.moveItem(at: from, to: to)
        }, commit: {}))
        XCTAssertFalse(manager.fileExists(atPath: second.path))
        try ArchiveDeletionTransaction.recoverPending(files: [second, first], stagingRoot: staging)
        XCTAssertEqual(try Data(contentsOf: second), Data("old".utf8))
        try Data("new".utf8).write(to: second, options: .atomic)
        try ArchiveDeletionTransaction.run(files: [second, first], stagingRoot: staging, commit: {})
        XCTAssertFalse(manager.fileExists(atPath: first.path)); XCTAssertFalse(manager.fileExists(atPath: second.path))
        XCTAssertTrue((try manager.contentsOfDirectory(atPath: staging.path)).isEmpty)
    }

    func testInterruptedDeletionWithRecreatedFileRetainsBothUntilSuccessfulRetry() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let original = root.appendingPathComponent("cache"), staging = root.appendingPathComponent("staging")
        let abandoned = staging.appendingPathComponent("interrupted")
        try manager.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: abandoned.appendingPathComponent("0"))
        try Data("new".utf8).write(to: original)
        XCTAssertThrowsError(try ArchiveDeletionTransaction.run(files: [original], stagingRoot: staging, commit: { throw CocoaError(.fileWriteOutOfSpace) })) {
            XCTAssertEqual(($0 as? CocoaError)?.code, .fileWriteOutOfSpace)
        }
        XCTAssertEqual(try Data(contentsOf: original), Data("new".utf8))
        XCTAssertEqual(try Data(contentsOf: abandoned.appendingPathComponent("0")), Data("old".utf8))
        XCTAssertTrue(manager.fileExists(atPath: abandoned.appendingPathComponent("recovery-copy").path))
        try ArchiveDeletionTransaction.run(files: [original], stagingRoot: staging, commit: {})
        XCTAssertFalse(manager.fileExists(atPath: original.path))
        XCTAssertTrue((try manager.contentsOfDirectory(atPath: staging.path)).isEmpty)
    }

    func testCleanupFailureCanBeRetriedAfterCommit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("backup"), staging = root.appendingPathComponent("staging")
        try Data("backup".utf8).write(to: file)
        var committed = false
        XCTAssertThrowsError(try ArchiveDeletionTransaction.run(files: [file], stagingRoot: staging, remove: { _ in throw CocoaError(.fileWriteNoPermission) }, commit: { committed = true }))
        XCTAssertTrue(committed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try ArchiveDeletionTransaction.run(files: [file], stagingRoot: staging, commit: {})
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: staging.path)).isEmpty)
    }
}
