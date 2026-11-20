package cn.gd306.tideenglish.core

import cn.gd306.tideenglish.LearningSnapshot
import cn.gd306.tideenglish.LearningWriteQueue
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PracticeWorkflowTest {
    @Test fun dailyLimitDoesNotUseOrChangeTheRegularPreference() {
        val preferences = Preferences(sessionMinutes = 30)
        assertEquals(5, practiceSessionMinutes("daily", preferences.sessionMinutes))
        assertEquals(30, practiceSessionMinutes("correction", preferences.sessionMinutes))
        assertEquals(30, practiceSessionMinutes(null, preferences.sessionMinutes))
        assertEquals(30, preferences.sessionMinutes)
    }

    @Test fun lateReplyFromThePreviousProviderIsRejected() = runTest {
        val (archive, source) = history("Yo querer té.")
        var allowed = true
        val failure = runCatching {
            requestPracticeCorrection(source, { archive.takeIf { allowed } }) {
                allowed = false
                PracticeCorrectionResult(true, "Yo quiero té.", "Conjugate the verb.")
            }
        }.exceptionOrNull() as? CorrectionFailure
        assertEquals(CorrectionProblem.STALE, failure?.problem)
    }

    @Test fun changedSourceRevisionDuringTheRequestIsRejected() = runTest {
        val (archive, source) = history("Yo querer té.")
        var current = archive
        val failure = runCatching {
            requestPracticeCorrection(source, { current }) {
                val updated = archive.sessions.single().copy(fragments = archive.sessions.single().fragments.toMutableList())
                updated.correctFragment(updated.fragments.single().id, "Yo quiero café.")
                current = archive.copy(sessions = mutableListOf(updated))
                PracticeCorrectionResult(true, "Yo quiero té.", "Conjugate the verb.")
            }
        }.exceptionOrNull() as? CorrectionFailure
        assertEquals(CorrectionProblem.STALE, failure?.problem)
    }

    @Test fun oversizeUnicodeSourceNeverInvokesTheProvider() = runTest {
        val (archive, source) = history("✨".repeat(2001))
        var calls = 0
        val failure = runCatching {
            requestPracticeCorrection(source, { archive }) {
                calls++
                PracticeCorrectionResult(false, "", "")
            }
        }.exceptionOrNull() as? CorrectionFailure
        assertEquals(0, calls)
        assertEquals(CorrectionProblem.INPUT_LIMIT, failure?.problem)
    }

    @Test fun malformedCorrectionIsAnErrorAndNoChangeRemainsAResult() = runTest {
        val (archive, source) = history("Yo quiero té.")
        val failure = runCatching {
            requestPracticeCorrection(source, { archive }) {
                PracticeCorrectionResult(true, "Yo quisiera té.", "")
            }
        }.exceptionOrNull() as? CorrectionFailure
        assertEquals(CorrectionProblem.RESPONSE, failure?.problem)
        assertNull(requestPracticeCorrection(source, { archive }) {
            PracticeCorrectionResult(false, "", "")
        })
    }

    @Test fun aCandidateDoesNotMutateAnyPreviouslyPublishedPracticeList() {
        val first = SavedExpression(languageID = "es", text = "té", meaning = "tea", context = "Quiero té.")
        val second = SavedExpression(languageID = "es", text = "leche", meaning = "milk", context = "Quiero leche.")
        val old = Archive(practice = PracticeLibrary(expressions = mutableListOf(first)))
        val candidate = old.editPractice { it.saveExpression(second) }
        assertEquals(listOf(first, second), candidate.practice!!.expressions)
        assertEquals(listOf(first), old.practice!!.expressions)
    }

    @Test fun failedPracticeCommitDoesNotLeakIntoQueuedSnapshots() = runTest {
        val first = SavedExpression(languageID = "es", text = "té", meaning = "tea", context = "Quiero té.")
        val second = SavedExpression(languageID = "es", text = "leche", meaning = "milk", context = "Quiero leche.")
        val before = LearningSnapshot(Archive(practice = PracticeLibrary(expressions = mutableListOf(first))))
        val gate = CompletableDeferred<Unit>()
        var current = before
        var disk = before
        var failNext = true
        val queue = LearningWriteQueue(backgroundScope, { current }, { current = it }, { false },
            { gate.await(); disk = it }, {
                if (failNext) {
                    failNext = false
                    assertEquals(listOf(first, second), it.archive.practice!!.expressions)
                    throw IOException("disk full")
                }
                disk = it
            }, {})
        queue.persist(before)
        runCurrent()
        val saving = async {
            runCatching {
                queue.mutate({ candidate -> candidate.copy(archive = candidate.archive.editPractice { it.saveExpression(second) }) },
                    onCommit = { error("A failed write must not publish success") })
            }
        }
        runCurrent()
        current = before.copy(archive = before.archive.copy(preferences = Preferences(interests = "preserved")))
        queue.persist(current)
        gate.complete(Unit)
        assertTrue(saving.await().exceptionOrNull() is IOException)
        runCurrent()
        assertEquals(listOf(first), current.archive.practice!!.expressions)
        assertEquals(listOf(first), disk.archive.practice!!.expressions)
        assertEquals("preserved", disk.archive.preferences.interests)
    }

    @Test fun cachedTranslationSearchUsesCurrentRevisionAndMeaningLanguage() {
        val (archive, _) = history("Yo quiero té.")
        val record = archive.sessions.single()
        val passage = record.passages.single()
        record.translations[MeaningRequest.cacheKey(passage.revisionKey, "English")] = "I would like tea."
        record.translations["French::${passage.revisionKey}"] = "Je voudrais du thé."
        assertTrue(record.matchesPracticeSearch("like tea", "English", record.title))
        assertFalse(record.matchesPracticeSearch("like tea", "French", record.title))
        assertEquals("Je voudrais du thé.", record.cachedPracticeTranslation(passage, "French"))
        record.correctFragment(passage.fragments.single().id, "Yo quiero agua.")
        assertFalse(record.matchesPracticeSearch("like tea", "English", record.title))
    }

    @Test fun changingOrDeletingTheSourceInvalidatesSavedCorrectionsOnlyInTheCandidate() = runTest {
        val (archive, source) = history("Yo querer té.")
        val correction = requestPracticeCorrection(source, { archive }) {
            PracticeCorrectionResult(true, "Yo quiero té.", "Conjugate the verb.")
        }!!
        val saved = archive.editPractice { assertTrue(it.saveCorrection(correction, archive.sessions)) }
        val rehearsal = PracticeIntent.Rehearsal(correction)
        val spanish = LanguageRegistry.get("es")!!
        assertTrue(rehearsal.theme(spanish, saved)!!.situation.contains("Yo quiero té."))
        val revised = archive.sessions.single().copy(fragments = archive.sessions.single().fragments.toMutableList())
        revised.correctFragment(revised.fragments.single().id, "Yo prefiero té.")
        val edited = saved.withPracticeSources(mutableListOf(revised))
        assertTrue(edited.practice!!.corrections.isEmpty())
        assertNull(rehearsal.theme(spanish, edited))
        assertTrue(saved.withPracticeSources(mutableListOf()).practice!!.corrections.isEmpty())
        assertEquals(listOf(correction), saved.practice!!.corrections)
    }

    @Test fun aProviderThatCompletesDespiteCancellationCannotPublishItsReply() = runTest {
        val (archive, source) = history("Yo querer té.")
        val delivery = CompletableDeferred<Unit>()
        var published = false
        val job = launch {
            requestPracticeCorrection(source, { archive }) {
                withContext(NonCancellable) { delivery.await() }
                PracticeCorrectionResult(true, "Yo quiero té.", "Conjugate the verb.")
            }
            published = true
        }
        runCurrent()
        job.cancel()
        delivery.complete(Unit)
        job.join()
        assertFalse(published)
    }

    @Test fun finalAssessmentPersistsAssistedEvidenceOnlyForCorrectionPractice() {
        for (kind in listOf(null, "daily", "correction")) {
            val (archive, _) = history("Yo quiero té.")
            val record = archive.sessions.single().copy(practiceKind = kind)
            val passage = record.passages.single()
            val evidence = WordProposal("té", "tea", "té", EvidenceKind.independent, 0.95,
                listOf(passage.fragments.single().id), "té", "es")
            val assessment = Assessment(passage.id, passage.revisionKey, Outcome.success, 1, "", "", listOf(evidence))
            val saved = FinalAssessmentResult(record.id, "es", assessment).applying(record)!!
            val decoded = ArchiveCodec.decode(ArchiveCodec.encode(Archive(sessions = mutableListOf(saved))))
            assertEquals(if (kind == "correction") EvidenceKind.assisted else EvidenceKind.independent,
                decoded.sessions.single().assessments.single().words.single().kind)
        }
    }

    private fun history(text: String): Pair<Archive, CorrectionSource> {
        val session = SessionRecord(languageID = "es", endedAt = nowSeconds())
        session.append(Fragment(speaker = Speaker.user, text = text, startMS = 0, endMS = 10))
        val passage = session.passages.single()
        return Archive(sessions = mutableListOf(session)) to
            CorrectionSource(session.id, passage.id, passage.revisionKey, passage.text, session.languageID)
    }
}
