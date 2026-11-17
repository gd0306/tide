import XCTest
@testable import TideEnglishCore

final class ImportReliabilityTests: XCTestCase {
    func testFailedWriterLeavesArchiveUnchangedAndSuccessfulWriterPersistsCandidate() throws {
        var incoming = Archive()
        incoming.sessions = [SessionRecord()]
        let data = try incoming.encoded()
        var transaction = ArchiveImportTransaction(archive: Archive())
        XCTAssertThrowsError(try transaction.importData(data) { _ in throw CocoaError(.fileWriteOutOfSpace) })
        XCTAssertEqual(transaction.archive.sessions.count, 0)
        var saved = Data()
        try transaction.importData(data) { saved = $0 }
        XCTAssertEqual(transaction.archive.sessions.count, 1)
        XCTAssertEqual(try Archive.decode(saved).sessions.count, 1)
    }
    func testRecoveryExportRemovesPrivateTicketsAndRejectsUnparseablePayload() throws {
        let payload = Data(#"{"schemaVersion":2,"iosFinalAssessments":[{"provider":"private"}],"other":"retained"}"#.utf8)
        let exported = try ArchiveRecoveryExport.sanitized(payload)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        XCTAssertNil(root["iosFinalAssessments"])
        XCTAssertEqual(root["other"] as? String, "retained")
        XCTAssertThrowsError(try ArchiveRecoveryExport.sanitized(Data("not json".utf8))) { error in
            XCTAssertEqual(error.localizedDescription, "The original record can’t be safely exported. It remains on this device.")
        }
    }
    func testImportedUnfinishedSessionIsClosed() throws {
        var incoming = Archive()
        incoming.sessions = [SessionRecord()]
        var transaction = ArchiveImportTransaction(archive: Archive())
        try transaction.importData(incoming.encoded()) { _ in }
        let merged = transaction.archive
        XCTAssertNotNil(merged.sessions[0].endedAt)
        XCTAssertEqual(merged.sessions[0].endReason, "Imported unfinished conversation")
    }
}
