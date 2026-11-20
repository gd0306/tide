package cn.gd306.tideenglish

import cn.gd306.tideenglish.core.*
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LearningWriteQueueTest {
    @Test fun importBarrierAbsorbsOldQueuedSnapshots() = runTest {
        val gate = CompletableDeferred<Unit>()
        var current = LearningSnapshot(Archive())
        var disk = current
        val queue = LearningWriteQueue(backgroundScope, { current }, { current = it }, { false },
            { snapshot -> gate.await(); disk = snapshot }, { snapshot -> disk = snapshot }, {})
        queue.persist(current)
        runCurrent()
        val incoming = Archive(sessions = mutableListOf(SessionRecord(languageID = "es")))
        val importing = async { queue.importData(ArchiveCodec.encode(incoming)) }
        runCurrent()
        current = current.copy(archive = current.archive.copy(preferences = current.archive.preferences.copy(interests = "latest")))
        queue.persist(current)
        gate.complete(Unit)
        importing.await(); runCurrent()
        assertEquals(1, disk.archive.sessions.size)
        assertEquals("latest", disk.archive.preferences.interests)
        assertEquals(1, current.archive.sessions.size)
    }

    @Test fun failedImportKeepsCurrentAndFlushesQueuedSnapshot() = runTest {
        val gate = CompletableDeferred<Unit>()
        var current = LearningSnapshot(Archive())
        var disk = current
        var failCandidate = true
        val queue = LearningWriteQueue(backgroundScope, { current }, { current = it }, { false },
            { snapshot -> gate.await(); disk = snapshot }, { snapshot ->
                if (failCandidate) { failCandidate = false; throw IOException("disk full") }
                disk = snapshot
            }, {})
        queue.persist(current); runCurrent()
        val incoming = Archive(sessions = mutableListOf(SessionRecord(languageID = "es")))
        val importing = async { runCatching { queue.importData(ArchiveCodec.encode(incoming)) } }
        runCurrent()
        current = current.copy(archive = current.archive.copy(preferences = current.archive.preferences.copy(interests = "kept")))
        queue.persist(current); gate.complete(Unit)
        assertTrue(importing.await().isFailure); runCurrent()
        assertEquals(0, current.archive.sessions.size)
        assertEquals(0, disk.archive.sessions.size)
        assertEquals("kept", disk.archive.preferences.interests)
    }

    @Test fun failedSecondBarrierCannotResurrectEarlierRevisionOrCorrection() = runTest {
        for (enqueueAfterCommit in listOf(false, true)) {
            val gate = CompletableDeferred<Unit>()
            val record = SessionRecord(languageID = "fr", endedAt = nowSeconds()).apply {
                append(Fragment(speaker = Speaker.user, text = "Je aller hier.", startMS = 0, endMS = 100))
            }
            val passage = record.passages.single()
            val correction = SavedCorrection(languageID = "fr", original = passage.text, corrected = "Je suis allé hier.",
                explanation = "Use the past tense.", sourceSessionID = record.id, sourcePassageID = passage.id,
                revisionKey = passage.revisionKey)
            val original = Archive(sessions = mutableListOf(record),
                practice = PracticeLibrary(corrections = mutableListOf(correction)))
            var current = LearningSnapshot(original)
            var disk = current
            val queue = LearningWriteQueue(backgroundScope, { current }, { current = it }, { false },
                { snapshot -> gate.await(); disk = snapshot }, { disk = it }, {})

            fun enqueuePreference() {
                val latest = current.archive
                current = current.copy(archive = latest.copy(preferences = latest.preferences.copy(interests = "latest preference")))
                queue.persist(current)
            }
            suspend fun edit(text: String, onCommit: () -> Unit = {}) {
                queue.mutate({ snapshot ->
                    snapshot.copy(archive = snapshot.archive.reviseHistoryPassage(record.id, passage.id, passage.revisionKey, text))
                }, onCommit)
            }

            queue.persist(current)
            runCurrent()
            val first = async {
                edit("Je suis allé hier.") { if (enqueueAfterCommit) enqueuePreference() }
            }
            val second = async { runCatching { edit("Un autre texte.") } }
            runCurrent()
            if (!enqueueAfterCommit) enqueuePreference()
            gate.complete(Unit)
            first.await()
            assertTrue(second.await().exceptionOrNull() is CorrectionFailure)
            runCurrent()

            for (snapshot in listOf(current, disk)) {
                val revised = snapshot.archive.sessions.single().passages.single()
                assertEquals("Je suis allé hier.", revised.text)
                assertEquals(1, revised.fragments.single().revision)
                assertTrue(snapshot.archive.practice!!.corrections.isEmpty())
                assertEquals("latest preference", snapshot.archive.preferences.interests)
            }
        }
    }
}
