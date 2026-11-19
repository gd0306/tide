import XCTest
@testable import TideEnglishCore

final class PracticeCoreTests: XCTestCase {
    func testDailyLimitDoesNotAffectOtherSessionsOrPreferences() {
        var archive = Archive()
        archive.preferences.sessionMinutes = 25
        var session = SessionRecord()
        for (kind, expected) in [(nil, 25), ("daily", 5), ("correction", 25)] as [(String?, Int)] {
            session.practiceKind = kind
            XCTAssertEqual(session.practiceMinutes(regular: archive.preferences.sessionMinutes), expected)
        }
        XCTAssertEqual(archive.preferences.sessionMinutes, 25)
    }
    func testHistoryTranslationUsesCurrentRevisionAndSupportsOldCaches() {
        var session = SessionRecord(languageID: "fr")
        session.append(Fragment(id: "p", speaker: .user, text: "Je vais hier.", startMS: 0, endMS: 1))
        let passage = session.passages[0], key = passage.revisionKey
        let current = MeaningRequest.cacheKey(revisionKey: key, language: "English")
        session.translations = [key: "oldest", "English::" + key: "legacy", current: "current"]
        XCTAssertEqual(session.cachedTranslation(for: passage, meaningLanguage: "English"), "current")
        session.translations.removeValue(forKey: current)
        XCTAssertEqual(session.cachedTranslation(for: passage, meaningLanguage: "English"), "legacy")
        session.translations.removeValue(forKey: "English::" + key)
        XCTAssertEqual(session.cachedTranslation(for: passage, meaningLanguage: "English"), "oldest")
        session.correctFragment(id: "p", text: "Je suis allé hier.")
        XCTAssertNil(session.cachedTranslation(for: session.passages[0], meaningLanguage: "English"))
    }
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
    func testSharedWhitespaceRules() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../packages/fixtures/cross-platform/practice-whitespace.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for item in try XCTUnwrap(root["cases"] as? [[String: Any]]) {
            let text = try XCTUnwrap(item["text"] as? String), blank = try XCTUnwrap(item["blank"] as? Bool)
            let expression = SavedExpression(languageID: "es", text: text, meaning: "m", context: "c")
            XCTAssertEqual((try? PracticeLibrary(expressions: [expression]).validate()) == nil, blank, text.debugDescription)
            if let expected = item["normalized"] as? String {
                var library = PracticeLibrary(); let first = try library.saveExpression(expression)
                let second = try library.saveExpression(SavedExpression(languageID: "es", text: expected, meaning: "m", context: "c"))
                XCTAssertEqual(first.id, second.id)
                if expected != "hola" {
                    let plain = try library.saveExpression(SavedExpression(languageID: "es", text: "hola", meaning: "m", context: "c"))
                    XCTAssertNotEqual(first.id, plain.id)
                }
            }
        }
    }
    func testMergeDiscardsStaleIncomingBeforeCapacityCheck() throws {
        var old = SessionRecord(languageID: "es"); old.append(Fragment(id: "p", speaker: .user, text: "wrong", startMS: 0, endMS: 1))
        let oldP = old.passages[0]; var current = old; current.correctFragment(id: "p", text: "new")
        let currentP = current.passages[0]
        let existing = (0..<2000).map { _ in SavedCorrection(languageID: "es", original: currentP.text, corrected: "newer", explanation: "m", sourceSessionID: current.id, sourcePassageID: currentP.id, revisionKey: currentP.revisionKey) }
        let stale = SavedCorrection(languageID: "es", original: oldP.text, corrected: "right", explanation: "m", sourceSessionID: old.id, sourcePassageID: oldP.id, revisionKey: oldP.revisionKey)
        var local = Archive(); local.sessions = [current]; local.practice = PracticeLibrary(corrections: existing)
        var incoming = Archive(); incoming.sessions = [old]; incoming.practice = PracticeLibrary(corrections: [stale])
        XCTAssertEqual(try local.merging(incoming).practice?.corrections.count, 2000)
    }
    func testFalseAndCanonicalCorrectionWithValidSource() {
        var session = SessionRecord(languageID: "es"); session.append(Fragment(id: "p", speaker: .user, text: "café", startMS: 0, endMS: 1))
        let p = session.passages[0]
        for result in [PracticeCorrectionResult(hasCorrection: false, corrected: "casa", explanation: "x"), PracticeCorrectionResult(hasCorrection: true, corrected: "cafe\u{301}", explanation: "x")] {
            XCTAssertNil(result.correction(languageID: "es", original: p.text, sourceSessionID: session.id, sourcePassageID: p.id, revisionKey: p.revisionKey, sessions: [session]))
        }
    }
    func testRejectsQuotedPracticeDates() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../packages/fixtures/cross-platform/practice-archive.json")
        let source = try String(contentsOf: url, encoding: .utf8)
        for number in ["800000002", "800000004", "800000005"] {
            let altered = source.replacingOccurrences(of: ":" + number, with: ":\"" + number + "\"")
            XCTAssertNotEqual(altered, source)
            XCTAssertThrowsError(try Archive.decode(Data(altered.utf8)))
        }
    }
    func testSharedPracticeDateTokens() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../packages/fixtures/cross-platform")
        let source = try String(contentsOf: directory.appendingPathComponent("practice-archive.json"), encoding: .utf8)
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("practice-date-tokens.json"))) as? [String: [String]])
        for key in ["valid", "invalid"] {
            for token in try XCTUnwrap(cases[key]) {
                for number in ["800000002", "800000004", "800000005"] {
                    let altered = source.replacingOccurrences(of: ":" + number, with: ":" + token)
                    XCTAssertNotEqual(altered, source)
                    if key == "valid" { XCTAssertNoThrow(try Archive.decode(Data(altered.utf8)), token) }
                    else { XCTAssertThrowsError(try Archive.decode(Data(altered.utf8)), token) }
                }
            }
        }
    }
}

extension PracticeCoreTests {
    @MainActor func testPracticeFixtureTypedReplyAndFinalizationNeverAccessLiveProvider() async throws {
        var keyReads = 0, networkCalls = 0, saved = false
        let mode = PracticeProviderMode.fixture
        let response = try await mode.response(purpose: "typed_reply", fixture: { $0 }, provider: {
            keyReads += 1; networkCalls += 1
            return "live"
        })
        mode.finalize(saveLocal: { saved = true }, provider: { keyReads += 1; networkCalls += 1 })
        XCTAssertNotEqual(response, "live")
        XCTAssertTrue(saved)
        XCTAssertEqual(keyReads, 0)
        XCTAssertEqual(networkCalls, 0)
    }

    func testPracticeKeySetupRequiresSavedKeyAndExplicitlyResolvesOriginalIntent() throws {
        var archive = Archive()
        archive.preferences.sessionMinutes = 15
        var session = SessionRecord(languageID: "en")
        session.append(Fragment(id: "sample", speaker: .user, text: "I goes.", startMS: 0, endMS: 40))
        session.endedAt = .now; archive.sessions = [session]
        let passage = session.passages[0]
        let correction = SavedCorrection(languageID: "en", original: passage.text, corrected: "I go.", explanation: "Subject agreement.",
            sourceSessionID: session.id, sourcePassageID: passage.id, revisionKey: passage.revisionKey)
        archive.practice = PracticeLibrary(corrections: [correction])
        let language = try XCTUnwrap(LanguageRegistry.module(for: "en"))
        let plan = try XCTUnwrap(DailyPracticePlan.make(languageID: "en", words: []))
        for intent in [PracticeStart.daily(plan), .correction(correction)] {
            var setup = PracticeKeySetup()
            setup.awaitKey(for: intent)
            XCTAssertNil(setup.finishSettings(), "Cancelling key setup must discard the old intent")
            setup.awaitKey(for: intent)
            setup.keyWasSaved = true
            let selected = try XCTUnwrap(setup.finishSettings())
            XCTAssertEqual(selected.kind, intent.kind)
            XCTAssertNil(setup.finishSettings())
            var record = SessionRecord(languageID: "en")
            record.practiceKind = selected.kind
            XCTAssertEqual(record.practiceMinutes(regular: archive.preferences.sessionMinutes), selected.kind == "daily" ? 5 : 15)
            XCTAssertEqual(selected.theme(language: language, archive: archive)?.id, selected.kind == "daily" ? plan.themeID : "correction")
            XCTAssertNil(selected.theme(language: try XCTUnwrap(LanguageRegistry.module(for: "fr")), archive: archive))
            if selected.kind == "correction" {
                var deleted = archive; deleted.sessions = []
                XCTAssertNil(selected.theme(language: language, archive: deleted))
            }
        }
        XCTAssertEqual(archive.preferences.sessionMinutes, 15)
    }

    func testCurrentTopicChosenAfterPracticeSurvivesImmediateNewStart() {
        let current = ConversationTheme("current", "Today's news", "", "", "", "source", 0)
        let prior = ConversationTheme("coffee", "Coffee", "", "", "", "order", 0)
        for kind in ["daily", "correction"] {
            var session = SessionRecord(languageID: "en", themeID: prior.id)
            session.practiceKind = kind; session.endedAt = .now
            XCTAssertEqual(session.nextTheme(selected: current, continuing: false)?.id, current.id)
            var switchedToNews = session
            switchedToNews.themeID = "current"
            XCTAssertEqual(switchedToNews.nextTheme(selected: current, continuing: false)?.id, current.id)
            XCTAssertNil(session.nextTheme(selected: prior, continuing: false))
            XCTAssertEqual(session.nextTheme(selected: prior, continuing: true)?.id, prior.id)
        }
    }

    @MainActor func testUnrepresentablePassageCannotInvokeCorrectionProviderAndBadOutputIsRetryable() async throws {
        func passage(text: String, id: String = "p") -> Passage {
            var session = SessionRecord(languageID: "en")
            session.append(Fragment(id: id, speaker: .user, text: text, startMS: 0, endMS: 20))
            return session.passages[0]
        }
        var calls = 0
        let none = #"{"hasCorrection":false,"corrected":"","explanation":""}"#
        for source in [passage(text: String(repeating: "e\u{301}", count: 1_001)), passage(text: "Hi", id: String(repeating: "i", count: 4_000))] {
            do {
                _ = try await PracticeCorrectionResult.request(passage: source) { calls += 1; return none }
                XCTFail("Unrepresentable source reached the provider")
            } catch { XCTAssertEqual(error as? PracticeCorrectionError, .unsupportedPassage) }
        }
        XCTAssertEqual(calls, 0)
        let boundary = passage(text: String(repeating: "e\u{301}", count: 1_000))
        let good = try await PracticeCorrectionResult.request(passage: boundary) { calls += 1; return none }
        XCTAssertFalse(good.hasCorrection)
        for bad in ["not JSON", #"{"hasCorrection":true,"corrected":"OK","explanation":""}"#] {
            do {
                _ = try await PracticeCorrectionResult.request(passage: boundary) { calls += 1; return bad }
                XCTFail("Malformed output accepted")
            } catch { XCTAssertEqual(error as? PracticeCorrectionError, .invalidResponse) }
        }
        XCTAssertEqual(calls, 3)
    }
}
