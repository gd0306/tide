import XCTest
@testable import TideEnglishCore

final class PracticeCoreTests: XCTestCase {
    func testLibraryDeduplicatesAndInvalidatesRevisions() throws {
        var session = SessionRecord(languageID: "es")
        session.append(Fragment(id: "p", speaker: .user, text: "Yo gusto café", startMS: 0, endMS: 1))
        let p = session.passages[0]
        var library = PracticeLibrary()
        let a = SavedExpression(languageID: "es", text: " Café ", meaning: "咖啡", context: "注文")
        XCTAssertEqual(try library.saveExpression(a).id, a.id)
        XCTAssertEqual(try library.saveExpression(SavedExpression(languageID: "es", text: "café", meaning: "coffee", context: "coffee")).id, a.id)
        let correction = SavedCorrection(languageID: "es", original: p.text, corrected: "Me gusta el café", explanation: "表达喜好", sourceSessionID: session.id, sourcePassageID: p.id, revisionKey: p.revisionKey)
        XCTAssertTrue(try library.saveCorrection(correction, sessions: [session]))
        session.correctFragment(id: "p", text: "Me gusta café")
        library.invalidateCorrections(sessions: [session])
        XCTAssertTrue(library.corrections.isEmpty)
        XCTAssertFalse(try library.saveCorrection(correction, sessions: [session]))
        library.deleteExpression(id: a.id)
        XCTAssertTrue(library.expressions.isEmpty)
    }
    func testPlanAndCorrectionResult() throws {
        let plan = try XCTUnwrap(DailyPracticePlan.make(languageID: "es", words: [], now: .now))
        XCTAssertNotNil(LanguageRegistry.module(for: "es")?.themes.first { $0.id == plan.themeID })
        XCTAssertTrue(plan.words.isEmpty)
        XCTAssertNil(DailyPracticePlan.make(languageID: "unknown", words: [], now: .now))
        XCTAssertNil(PracticeCorrectionResult(hasCorrection: false, corrected: "invented", explanation: "invented").correction(languageID: "es", original: "hola", sourceSessionID: UUID(), sourcePassageID: "p", revisionKey: "p:0", sessions: []))
    }
    func testDueWordsAreLimitedAndOrdered() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        func word(_ id: String, _ due: Double) -> WordState {
            WordState(id: id, lemma: id, meaning: "m", form: "f", example: "e", bars: 0, understandingCount: 0, independentCount: 0, lastSeen: now, dueAt: Date(timeIntervalSinceReferenceDate: due))
        }
        let words = [word("es|late", 90), word("es|early", 10), word("es|mid", 50), word("es|fourth", 95), word("es|future", 101), word("en|foreign", 1)]
        XCTAssertEqual(DailyPracticePlan.make(languageID: "es", words: words, now: now)?.words.map(\.id), ["es|early", "es|mid", "es|late"])
    }
    func testValidationAndMergePreservePreferences() throws {
        let good = SavedExpression(languageID: "es", text: "hola", meaning: "hello", context: "greeting")
        XCTAssertThrowsError(try PracticeLibrary(expressions: [SavedExpression(languageID: "unknown", text: "a", meaning: "b", context: "c")]).validate())
        XCTAssertThrowsError(try PracticeLibrary(expressions: [SavedExpression(languageID: "es", text: String(repeating: "a", count: 2001), meaning: "b", context: "c")]).validate())
        XCTAssertThrowsError(try PracticeLibrary(expressions: Array(repeating: good, count: 2001)).validate())
        var local = Archive(); local.preferences.meaningLanguage = "Chinese (Simplified)"
        var incoming = Archive(); incoming.practice = PracticeLibrary(expressions: [good]); incoming.preferences.meaningLanguage = "French"
        let merged = try local.merging(incoming)
        XCTAssertEqual(merged.preferences.meaningLanguage, "Chinese (Simplified)")
        XCTAssertEqual(merged.practice?.expressions.first?.id, good.id)
        XCTAssertEqual(try merged.merging(incoming).practice?.expressions.count, 1)
        var invalid = incoming; invalid.sessions = [SessionRecord()]; invalid.sessions[0].practiceKind = "other"
        XCTAssertThrowsError(try local.merging(invalid))
    }
    func testCorrectionResultIsBoundToExistingUnchangedSource() throws {
        var session = SessionRecord(languageID: "es")
        session.append(Fragment(id: "x", speaker: .user, text: "Yo gusta", startMS: 0, endMS: 1))
        let p = session.passages[0]
        let result = PracticeCorrectionResult(hasCorrection: true, corrected: "Me gusta", explanation: "Use me")
        func correction(_ sessions: [SessionRecord]) -> SavedCorrection? {
            result.correction(languageID: "es", original: p.text, sourceSessionID: session.id, sourcePassageID: p.id, revisionKey: p.revisionKey, sessions: sessions)
        }
        let saved = try XCTUnwrap(correction([session]))
        XCTAssertNil(PracticeCorrectionResult(hasCorrection: true, corrected: p.text, explanation: "none").correction(languageID: "es", original: p.text, sourceSessionID: session.id, sourcePassageID: p.id, revisionKey: p.revisionKey, sessions: [session]))
        var library = PracticeLibrary(corrections: [saved]); library.invalidateCorrections(sessions: [])
        XCTAssertTrue(library.corrections.isEmpty)
        XCTAssertNil(correction([]))
        session.correctFragment(id: "x", text: "Me gusta")
        XCTAssertNil(correction([session]))
    }
}
