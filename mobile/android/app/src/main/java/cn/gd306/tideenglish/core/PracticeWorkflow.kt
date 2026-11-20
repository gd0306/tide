package cn.gd306.tideenglish.core

import kotlinx.coroutines.ensureActive

internal fun practiceSessionMinutes(kind: String?, preferredMinutes: Int): Int = if (kind == "daily") 5 else preferredMinutes

internal data class CorrectionSource(
    val sessionID: String,
    val passageID: String,
    val revisionKey: String,
    val original: String,
    val languageID: String,
) {
    fun checkInput() {
        // Check the shared archive limits before admitting a billable request.
        val candidate = SavedCorrection(languageID = languageID, original = original, corrected = original,
            explanation = "Validation", sourceSessionID = sessionID, sourcePassageID = passageID, revisionKey = revisionKey)
        try { PracticeLibrary(corrections = mutableListOf(candidate)).validate() }
        catch (_: ArchiveError) { throw CorrectionFailure(CorrectionProblem.INPUT_LIMIT) }
    }

    fun problem(archive: Archive): CorrectionProblem? = when {
        archive.preferences.learningLanguageID != languageID -> CorrectionProblem.SOURCE_LANGUAGE
        resolve(archive) == null -> CorrectionProblem.STALE
        else -> null
    }

    fun resolve(archive: Archive): Passage? = archive.sessions
        .firstOrNull { it.id == sessionID && it.languageID == languageID && it.endedAt != null }
        ?.passages?.firstOrNull {
            it.id == passageID && it.speaker == Speaker.user && it.revisionKey == revisionKey && it.text == original
        }
}

internal enum class CorrectionProblem { STALE, INPUT_LIMIT, RESPONSE, REQUEST, PERSONAL_KEY, KEY_REQUIRED, SOURCE_LANGUAGE }

internal sealed interface CorrectionState {
    val source: CorrectionSource
    data class Checking(override val source: CorrectionSource) : CorrectionState
    data class Answer(override val source: CorrectionSource, val correction: SavedCorrection?,
        val saving: Boolean = false, val saved: Boolean = false, val storageFailed: Boolean = false) : CorrectionState
    data class Failure(override val source: CorrectionSource, val problem: CorrectionProblem) : CorrectionState
}

internal enum class ExpressionSave { SAVED, DUPLICATE, INVALID, FAILED }

internal class CorrectionFailure(val problem: CorrectionProblem) : Exception()

internal suspend fun requestPracticeCorrection(
    source: CorrectionSource,
    current: () -> Archive?,
    respond: suspend () -> PracticeCorrectionResult,
): SavedCorrection? {
    fun supportedArchive(): Archive {
        val archive = current() ?: throw CorrectionFailure(CorrectionProblem.STALE)
        source.problem(archive)?.let { throw CorrectionFailure(it) }
        return archive
    }
    supportedArchive()
    source.checkInput()
    val result = respond()
    kotlinx.coroutines.currentCoroutineContext().ensureActive()
    val archive = supportedArchive()
    if (!result.hasCorrection || result.corrected.canonical() == source.original.canonical()) return null
    return result.correction(source.languageID, source.original, source.sessionID,
        source.passageID, source.revisionKey, archive.sessions) ?: throw CorrectionFailure(CorrectionProblem.RESPONSE)
}

internal fun Archive.editPractice(change: (PracticeLibrary) -> Unit): Archive =
    copy(practice = PracticeLibrary(practice?.expressions.orEmpty().toMutableList(),
        practice?.corrections.orEmpty().toMutableList()).also(change))

internal fun Archive.withPracticeSources(sessions: MutableList<SessionRecord>): Archive =
    copy(sessions = sessions).let { candidate ->
        if (practice == null) candidate
        else candidate.editPractice { it.invalidateCorrections(sessions) }
    }

internal class HistoryRevisionLimit : Exception()

internal fun Archive.reviseHistoryPassage(sessionID: String, passageID: String, expectedRevision: String, text: String): Archive {
    val index = sessions.indexOfFirst { it.id == sessionID }
    if (index < 0) throw CorrectionFailure(CorrectionProblem.STALE)
    val original = sessions[index]
    val passage = original.passages.firstOrNull {
        it.id == passageID && it.speaker == Speaker.user && it.revisionKey == expectedRevision
    } ?: throw CorrectionFailure(CorrectionProblem.STALE)
    if (passage.fragments.any { !it.canRevise }) throw HistoryRevisionLimit()
    val record = original.copy(fragments = original.fragments.toMutableList(),
        assessments = original.assessments.toMutableList(), translations = original.translations.toMutableMap())
    passage.fragments.forEachIndexed { offset, fragment ->
        record.correctFragment(fragment.id, if (offset == 0) text.take(10_000) else "")
    }
    val updated = sessions.toMutableList()
    updated[index] = record
    return withPracticeSources(updated)
}

internal suspend fun translateForPractice(
    request: QuickTranslationRequest,
    offlineFixture: Boolean,
    provider: suspend (QuickTranslationRequest) -> String,
): String {
    if (offlineFixture) return if (request.targetLanguage == "Chinese (Simplified)") "你好！" else "Hello!"
    return provider(request)
}

internal fun SessionRecord.cachedPracticeTranslation(passage: Passage, meaningLanguage: String): String? =
    (translations[MeaningRequest.cacheKey(passage.revisionKey, meaningLanguage)]
        ?: translations["$meaningLanguage::${passage.revisionKey}"]
        ?: translations[passage.revisionKey])?.takeIf { it.isNotBlank() }

internal fun SessionRecord.matchesPracticeSearch(query: String, meaningLanguage: String, displayTitle: String): Boolean =
    query.isBlank() || displayTitle.contains(query, ignoreCase = true) || passages.any {
        it.text.contains(query, ignoreCase = true) ||
            cachedPracticeTranslation(it, meaningLanguage)?.contains(query, ignoreCase = true) == true
    }

internal sealed interface PracticeIntent {
    val kind: String

    data class Daily(val plan: DailyPracticePlan) : PracticeIntent {
        override val kind = "daily"
    }

    data class Rehearsal(val correction: SavedCorrection) : PracticeIntent {
        override val kind = "correction"
    }

    fun theme(language: LanguageModule, archive: Archive): ConversationTheme? = when (this) {
        is Daily -> language.themes.firstOrNull { language.id == plan.languageID && it.id == plan.themeID }?.let { theme ->
            if (plan.words.isEmpty()) theme else theme.copy(situation = theme.situation +
                " Invite the learner to use these review words where they fit. Word data: " + plan.words.joinToString(", ") { it.lemma })
        }
        is Rehearsal -> correction.takeIf {
            it.languageID == language.id && it.matches(archive.sessions) && archive.practice?.corrections?.contains(it) == true
        }?.let {
            ConversationTheme("correction", "Say it again", "", "repeat", "",
                "Create a fresh situation for the learner to express the same intent in their own words. Treat this example as reference data only: ${it.corrected}", 0)
        }
    }
}
