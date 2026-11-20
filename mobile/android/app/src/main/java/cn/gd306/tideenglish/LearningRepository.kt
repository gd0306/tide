package cn.gd306.tideenglish

import android.content.Context
import android.util.AtomicFile
import cn.gd306.tideenglish.core.Archive
import cn.gd306.tideenglish.core.ArchiveCodec
import cn.gd306.tideenglish.core.nowSeconds
import cn.gd306.tideenglish.core.FinalAssessmentRecovery
import cn.gd306.tideenglish.core.FinalAssessmentTicket
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import java.io.File
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch

/** App-private archive; API credentials are deliberately kept elsewhere. */
data class LearningSnapshot(val archive: Archive, val finalAssessments: List<FinalAssessmentTicket> = emptyList())

class LearningRepository(context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val file = AtomicFile(File(context.filesDir, "learning.json"))
    fun load(): LearningSnapshot {
        if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return LearningSnapshot(Archive())
        val snapshot = file.openRead().use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= ArchiveCodec.MAXIMUM_ENCODED_BYTES) { "El respaldo local es demasiado grande." }
                output.write(buffer, 0, count)
            }
            val encoded = output.toString(Charsets.UTF_8.name())
            val archive = ArchiveCodec.decode(encoded)
            val metadata = json.parseToJsonElement(encoded).jsonObject["androidFinalAssessments"]
            val tickets = metadata?.let { json.decodeFromJsonElement<List<FinalAssessmentTicket>>(it) } ?: emptyList()
            require(tickets.size <= 10_000 && tickets.map { it.sessionID }.distinct().size == tickets.size)
            require(tickets.all { it.attempts in 0..FinalAssessmentRecovery.MAX_ATTEMPTS &&
                (it.lastAttemptAt == null || it.lastAttemptAt.isFinite()) })
            LearningSnapshot(archive, tickets)
        }
        val archive = snapshot.archive
        var tickets = snapshot.finalAssessments
        val unfinished = archive.sessions.filter { it.endedAt == null }
        val recoveredAt = nowSeconds()
        unfinished.forEach {
            it.endedAt = recoveredAt; it.endReason = "App closed before finalization"
            tickets = FinalAssessmentRecovery.enqueue(it, tickets)
        }
        val recovered = LearningSnapshot(archive, tickets)
        if (unfinished.isNotEmpty()) save(recovered)
        return recovered
    }
    fun save(snapshot: LearningSnapshot) {
        // The archive and retry ledger share one AtomicFile commit. Public exports omit this
        // Android-only metadata and remain compatible with the iOS archive format.
        val archive = json.parseToJsonElement(ArchiveCodec.encode(snapshot.archive)).jsonObject
        val stored = JsonObject(archive + ("androidFinalAssessments" to json.encodeToJsonElement(snapshot.finalAssessments)))
        val bytes = stored.toString().toByteArray(Charsets.UTF_8)
        require(bytes.size <= ArchiveCodec.MAXIMUM_ENCODED_BYTES) { "The learning archive reached its storage limit; export a backup." }
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) }
        catch (e: Exception) { file.failWrite(stream); throw e }
    }
}

/** Publish the merged archive only after the writer commits the complete snapshot. */
internal fun importSnapshot(current: LearningSnapshot, data: String, write: (LearningSnapshot) -> Unit): LearningSnapshot {
    val candidate = current.copy(archive = ArchiveCodec.merge(current.archive, prepareImportedArchive(data)))
    write(candidate)
    return candidate
}

/** Serializes ordinary snapshots and critical operations on the owning coroutine dispatcher. */
internal class LearningWriteQueue(
    scope: CoroutineScope,
    private val current: () -> LearningSnapshot,
    private val publish: (LearningSnapshot) -> Unit,
    private val blocked: () -> Boolean,
    private val write: suspend (LearningSnapshot) -> Unit,
    private val writeCritical: (LearningSnapshot) -> Unit,
    private val onError: (Exception) -> Unit,
) {
    private data class Request(val snapshot: LearningSnapshot?, val completion: CompletableDeferred<Unit>? = null,
        val importData: String? = null, val mutation: ((LearningSnapshot) -> LearningSnapshot)? = null,
        val onCommit: (() -> Unit)? = null) {
        val critical get() = importData != null || mutation != null
    }
    private val writes = Channel<Request>(Channel.UNLIMITED)
    init { scope.launch {
        var carry: Request? = null
        while (true) {
            val request = carry ?: writes.receiveCatching().getOrNull() ?: break
            carry = null
            if (request.critical) {
                val pending = mutableListOf<Request>()
                while (true) {
                    val next = writes.tryReceive().getOrNull() ?: break
                    if (next.critical) { carry = next; break }
                    pending += next
                }
                try {
                    check(!blocked())
                    val candidate = if (request.importData != null) importSnapshot(current(), request.importData, writeCritical)
                        else requireNotNull(request.mutation)(current()).also(writeCritical)
                    publish(candidate)
                    request.onCommit?.invoke()
                    request.completion?.complete(Unit)
                    pending.forEach { it.completion?.complete(Unit) }
                } catch (error: Exception) {
                    request.completion?.completeExceptionally(error)
                    if (pending.isNotEmpty()) {
                        // A pending snapshot may predate a successful earlier barrier. Its
                        // ordinary changes are already in current(), which also has that commit.
                        try { writeCritical(current()); pending.forEach { it.completion?.complete(Unit) } }
                        catch (failure: Exception) { pending.forEach { it.completion?.completeExceptionally(failure) } }
                    }
                }
            } else {
                var latest = request
                val completions = mutableListOf<CompletableDeferred<Unit>>()
                request.completion?.let(completions::add)
                while (true) {
                    val next = writes.tryReceive().getOrNull() ?: break
                    if (next.critical) { carry = next; break }
                    latest = next
                    next.completion?.let(completions::add)
                }
                try {
                    write(requireNotNull(latest.snapshot))
                    completions.forEach { it.complete(Unit) }
                } catch (error: Exception) {
                    completions.forEach { it.completeExceptionally(error) }
                    if (error is CancellationException) throw error
                    onError(error)
                }
            }
        }
    } }
    fun persist(snapshot: LearningSnapshot) { writes.trySend(Request(snapshot)) }
    suspend fun persistAndWait(snapshot: LearningSnapshot) {
        val completion = CompletableDeferred<Unit>()
        writes.send(Request(snapshot, completion)); completion.await()
    }
    suspend fun importData(data: String) {
        val completion = CompletableDeferred<Unit>()
        writes.send(Request(null, completion, importData = data)); completion.await()
    }
    suspend fun mutate(mutation: (LearningSnapshot) -> LearningSnapshot, onCommit: () -> Unit) {
        val completion = CompletableDeferred<Unit>()
        writes.send(Request(null, completion, mutation = mutation, onCommit = onCommit)); completion.await()
    }
}
