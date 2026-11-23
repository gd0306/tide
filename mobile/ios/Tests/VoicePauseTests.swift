import XCTest
@testable import TideEnglishCore

final class VoicePauseTests: XCTestCase {
    func testVoiceActivityRestartsWaitEvenWithoutNewRecognitionText() {
        var buffer = VoicePauseBuffer(seconds: 10)
        XCTAssertTrue(buffer.update("I would like", at: 0))
        buffer.speech(at: 9)
        XCTAssertEqual(buffer.remaining(at: 10), 9)
        XCTAssertEqual(buffer.remaining(at: 19), 0)
    }

    func testFinalSegmentsStayTogetherUntilTheSelectedPauseExpires() {
        for seconds in [5, 10, 20, 30] {
            var buffer = VoicePauseBuffer(seconds: seconds)
            _ = buffer.update("I would like", at: 0)
            buffer.finishSegment()
            XCTAssertGreaterThan(buffer.remaining(at: 1) ?? 0, 0)
            _ = buffer.update("some coffee", at: 3)
            buffer.finishSegment()
            XCTAssertEqual(buffer.text, "I would like some coffee")
            XCTAssertGreaterThan(buffer.remaining(at: Double(seconds) + 2.9) ?? 0, 0)
            XCTAssertEqual(buffer.remaining(at: Double(seconds) + 3), 0)
        }
    }

    func testDuplicateTextDoesNotExtendPauseAndResetDiscardsPendingSpeech() {
        var buffer = VoicePauseBuffer()
        _ = buffer.update("hello", at: 0)
        XCTAssertFalse(buffer.update("hello", at: 4))
        XCTAssertEqual(buffer.remaining(at: 5), 0)
        buffer.reset()
        XCTAssertEqual(buffer.text, "")
        XCTAssertNil(buffer.remaining(at: 100))
        buffer.speech(at: 101)
        XCTAssertNil(buffer.remaining(at: 110))
    }

    func testOlderBackupsUseFiveSecondWait() throws {
        XCTAssertEqual(try Archive.decode(backup(pause: nil)).preferences.effectiveVoicePauseSeconds, 5)
    }

    func testPendingThirtySecondReplySuppressesFifteenSecondCheckIn() {
        var buffer = VoicePauseBuffer(seconds: 30)
        var activity = ConversationActivity(now: 0)
        _ = buffer.update("I am thinking", at: 1)
        activity.learnerEngaged(now: 1)
        XCTAssertEqual(activity.tick(now: 16, busy: buffer.hasPendingInput), .wait)
        XCTAssertEqual(activity.tick(now: 30, busy: buffer.hasPendingInput), .wait)
        XCTAssertGreaterThan(buffer.remaining(at: 30) ?? 0, 0)
        XCTAssertEqual(buffer.remaining(at: 31), 0)
    }

    private func backup(pause: Any?) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Archive().encoded()) as? [String: Any])
        var preferences = try XCTUnwrap(root["preferences"] as? [String: Any])
        preferences["voicePauseSeconds"] = pause
        root["preferences"] = preferences
        return try JSONSerialization.data(withJSONObject: root)
    }

    func testSelectedPauseSurvivesBackupRoundTrip() throws {
        for seconds in [5, 10, 20, 30] {
            let data = try Archive.decode(backup(pause: seconds)).encoded()
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let prefs = try XCTUnwrap(root["preferences"] as? [String: Any])
            XCTAssertEqual(prefs["voicePauseSeconds"] as? Int, seconds)
        }
    }

    func testUnsupportedPauseIsRejectedWithoutLosingExistingArchive() throws {
        for value: Any in [0, 7, 31, "10", 10.5, true] {
            XCTAssertThrowsError(try Archive.decode(backup(pause: value)))
        }
        XCTAssertNoThrow(try Archive.decode(backup(pause: nil)))
    }
}
