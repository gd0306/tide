package cn.gd306.tideenglish.core

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class VoicePauseTest {
    @Test fun voiceActivityRestartsWaitEvenWithoutNewRecognitionText() {
        val buffer = VoicePauseBuffer(10)
        assertTrue(buffer.update("I would like", 0.0))
        buffer.speech(9.0)
        assertEquals(9.0, buffer.remaining(10.0)!!, 0.0)
        assertEquals(0.0, buffer.remaining(19.0)!!, 0.0)
    }
    @Test fun finalSegmentsStayTogetherUntilTheSelectedPauseExpires() {
        for (seconds in listOf(5, 10, 20, 30)) {
            val buffer = VoicePauseBuffer(seconds)
            buffer.update("I would like", 0.0)
            buffer.finishSegment()
            assertTrue(buffer.remaining(1.0)!! > 0)
            buffer.update("some coffee", 3.0)
            buffer.finishSegment()
            assertEquals("I would like some coffee", buffer.text)
            assertTrue(buffer.remaining(seconds + 2.9)!! > 0)
            assertEquals(0.0, buffer.remaining(seconds + 3.0)!!, 0.0)
        }
    }
    @Test fun duplicateTextDoesNotExtendPauseAndResetDiscardsPendingSpeech() {
        val buffer = VoicePauseBuffer()
        buffer.update("hello", 0.0)
        assertFalse(buffer.update("hello", 4.0))
        assertEquals(0.0, buffer.remaining(5.0)!!, 0.0)
        buffer.reset()
        assertEquals("", buffer.text)
        assertNull(buffer.remaining(100.0))
        buffer.speech(101.0)
        assertNull(buffer.remaining(110.0))
    }
    @Test fun olderBackupsUseFiveSecondWait() {
        assertEquals(5, ArchiveCodec.decode(backup(null)).preferences.effectiveVoicePauseSeconds)
    }
    @Test fun pendingThirtySecondReplySuppressesFifteenSecondCheckIn() {
        val buffer = VoicePauseBuffer(30)
        val activity = ConversationActivity(0.0)
        buffer.update("I am thinking", 1.0)
        activity.learnerEngaged(1.0)
        assertEquals(ConversationActivity.Action.Wait, activity.tick(16.0, busy = buffer.hasPendingInput))
        assertEquals(ConversationActivity.Action.Wait, activity.tick(30.0, busy = buffer.hasPendingInput))
        assertTrue(buffer.remaining(30.0)!! > 0)
        assertEquals(0.0, buffer.remaining(31.0)!!, 0.0)
    }
    private fun backup(value: JsonElement?): String {
        val root = Json.parseToJsonElement(ArchiveCodec.encode(Archive())).jsonObject.toMutableMap()
        val prefs = root.getValue("preferences").jsonObject.toMutableMap()
        if (value == null) prefs.remove("voicePauseSeconds") else prefs["voicePauseSeconds"] = value
        root["preferences"] = JsonObject(prefs)
        return JsonObject(root).toString()
    }
    @Test fun selectedPauseSurvivesBackupRoundTrip() {
        for (seconds in listOf(5, 10, 20, 30)) {
            val restored = ArchiveCodec.decode(backup(JsonPrimitive(seconds)))
            val prefs = Json.parseToJsonElement(ArchiveCodec.encode(restored)).jsonObject.getValue("preferences").jsonObject
            assertEquals(JsonPrimitive(seconds), prefs["voicePauseSeconds"])
        }
    }
    @Test fun unsupportedPauseIsRejectedWithoutLosingExistingArchive() {
        for (value in listOf(JsonPrimitive(0), JsonPrimitive(7), JsonPrimitive(31), JsonPrimitive("10"), JsonPrimitive(10.5), JsonPrimitive(true))) {
            assertThrows(ArchiveError::class.java) { ArchiveCodec.decode(backup(value)) }
        }
        ArchiveCodec.decode(backup(null))
    }
}
