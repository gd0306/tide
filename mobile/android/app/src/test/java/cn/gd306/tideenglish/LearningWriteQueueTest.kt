package cn.gd306.tideenglish

import cn.gd306.tideenglish.core.Archive
import cn.gd306.tideenglish.core.ArchiveCodec
import cn.gd306.tideenglish.core.SessionRecord
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

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
}
