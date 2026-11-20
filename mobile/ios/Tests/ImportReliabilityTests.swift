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
    func testStartupReplacementNormalizesForeignBackup() throws {
        var incoming = Archive(), session = SessionRecord(languageID: "es")
        incoming.preferences.aiConsentVersion = 1
        session.practiceKind = "correction"
        session.append(Fragment(id: "p", speaker: .user, text: "la radio", startMS: 0, endMS: 1))
        let p = session.passages[0]
        session.assessments = [Assessment(passageID: p.id, revisionKey: p.revisionKey, outcome: .success,
            suggestedLevel: 1, nextGoal: "hola", capability: "hola",
            words: [WordProposal(lemma: "radio", meaning: "radio", form: "radio", kind: .independent,
                confidence: 0.95, sourceIDs: ["p"], quote: p.text, language: "es")])]
        incoming.sessions = [session]
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: incoming.encoded()) as? [String: Any])
        root["iosFinalAssessments"] = [["provider": "foreign"]]
        let payload = try ArchiveRecoveryExport.replacement(JSONSerialization.data(withJSONObject: root))
        let saved = try Archive.decode(payload)
        XCTAssertNil(saved.preferences.aiConsentVersion)
        XCTAssertEqual(saved.sessions.first?.assessments.first?.words.first?.kind, .assisted)
        XCTAssertEqual(saved.sessions.first?.endReason, "Imported unfinished conversation")
        XCTAssertNotNil(saved.sessions.first?.endedAt)
        XCTAssertNil((try JSONSerialization.jsonObject(with: payload) as? [String: Any])?["iosFinalAssessments"])
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
