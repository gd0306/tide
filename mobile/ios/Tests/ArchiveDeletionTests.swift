import XCTest
@testable import TideEnglishCore

final class ArchiveDeletionTests: XCTestCase {
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
