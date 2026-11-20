package cn.gd306.tideenglish

import android.Manifest
import android.os.Build
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import cn.gd306.tideenglish.core.*
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Runs in the separate .uitest package with a synthetic endpoint, key and replies. */
@RunWith(AndroidJUnit4::class)
class PracticeFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private lateinit var vm: TideEnglishViewModel
    private lateinit var oldPreferences: Preferences
    private lateinit var oldModel: ProviderConfiguration
    private var correctionCalls = 0
    private val fixtureModel = ProviderConfiguration(ModelProvider.CUSTOM, "fixture-model", "https://offline.invalid/v1")
    private val history = SessionRecord(languageID = "fr", title = "A fixture visit", endedAt = nowSeconds()).apply {
        append(Fragment(speaker = Speaker.user, text = "Je aller hier.", startMS = 0, endMS = 1_000))
        translations[MeaningRequest.cacheKey(passages.single().revisionKey, "English")] = "My visit yesterday."
    }

    @Before fun setup() {
        val instrument = InstrumentationRegistry.getInstrumentation()
        val target = instrument.targetContext
        assertTrue(target.packageName.endsWith(".uitest"))
        if (Build.VERSION.SDK_INT >= 28) {
            instrument.uiAutomation.grantRuntimePermission(target.packageName, Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= 33) instrument.uiAutomation.grantRuntimePermission(
                target.packageName, Manifest.permission.POST_NOTIFICATIONS)
        }
        vm = compose.awaitHistoryLoaded()
        compose.runOnIdle {
            oldPreferences = vm.archive.preferences.copy()
            oldModel = vm.modelConfiguration
            vm.installOfflinePracticeFixture {
                correctionCalls++
                if (correctionCalls == 1) throw IOException("Synthetic provider failure")
                PracticeCorrectionResult(true, "Je suis allé hier.", "Use the past tense for yesterday.")
            }
            assertTrue(vm.updateModelConfiguration(fixtureModel))
            vm.deleteKey()
            vm.updatePreferences(oldPreferences.copy(learningLanguageID = "fr", meaningLanguage = "English",
                sessionMinutes = 30, hasOnboarded = true, aiConsentVersion = null))
        }
        onMain { assertTrue(vm.importData(ArchiveCodec.encode(Archive(sessions = mutableListOf(history))))) }
    }

    @After fun cleanup() {
        if (!::oldPreferences.isInitialized) return
        compose.runOnIdle {
            if (vm.isRunning) vm.end()
            vm.dismissCorrection()
            vm.cancelPractice()
            vm.resetConversation()
        }
        onMain {
            vm.archive.practice?.expressions?.filter { it.sourceSessionID == history.id }?.forEach {
                vm.deletePracticeItem(it.id, correction = false)
            }
            vm.archive.sessions.filter { it.id == history.id || (it.languageID == "fr" && it.startedAt >= history.startedAt && it.practiceKind != null) }
                .forEach { vm.deleteSession(it.id) }
        }
        compose.runOnIdle {
            vm.deleteKey()
            vm.updateModelConfiguration(oldModel)
            vm.updatePreferences(oldPreferences)
        }
    }

    @Test fun dailyPreviewWaitsForStartAndPreservesIntentThroughKeyAndConsent() {
        compose.onNodeWithTag("daily-practice-open").performClick()
        compose.onNodeWithTag("daily-practice-preview").assertIsDisplayed()
        compose.onNodeWithText("Answer a question about this scene in your own words.").assertExists()
        compose.onNodeWithTag("ai-consent-title").assertDoesNotExist()
        compose.onNodeWithTag("api-key-input").assertDoesNotExist()
        compose.onNodeWithTag("start-daily-practice").performScrollTo().performClick()
        saveFixtureKeyInModelDialog()
        compose.onNodeWithTag("confirm-practice-start").assertIsDisplayed()
        compose.runOnIdle {
            assertFalse(vm.isRunning)
            assertEquals("daily", vm.pendingPractice?.kind)
        }
        compose.onNodeWithTag("continue-practice").performClick()
        compose.onNodeWithTag("ai-consent-agree").performScrollTo().performClick()
        compose.runOnIdle {
            assertTrue(vm.isRunning)
            assertEquals("daily", vm.session?.practiceKind)
            assertEquals(30, vm.archive.preferences.sessionMinutes)
            assertEquals(0, correctionCalls)
        }
        compose.onNodeWithText("Type instead").performClick()
        compose.onNodeWithTag("typed-reply-input").performTextInput("Merci pour le café.")
        compose.onNodeWithTag("typed-reply-send").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals("Merci pour le café.", vm.session!!.passages.first { it.speaker == Speaker.user }.text)
        }
        compose.onNodeWithTag("tab-words").performClick()
        compose.onNodeWithTag("words-screen").performScrollToNode(hasTestTag("translation-toggle"))
        compose.onNodeWithTag("translation-toggle").performClick()
        compose.onNodeWithTag("words-screen").performScrollToNode(hasTestTag("translation-input"))
        compose.onNodeWithTag("translation-input").performTextInput("Bonjour")
        compose.onNodeWithTag("translation-output").assertDoesNotExist()
        compose.runOnIdle {
            vm.end()
            assertEquals("daily", vm.archive.sessions.first { it.id == vm.session!!.id }.practiceKind)
            assertEquals(0, vm.session!!.assessments.size)
        }
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("translation-output").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("translation-output").assertTextContains("Hello!")
    }

    @Test fun historyFromAnotherLanguageShowsWhySentenceCheckIsUnavailable() {
        compose.runOnIdle {
            vm.selectLanguage("en")
            vm.saveKey("synthetic-practice-key")
            vm.updatePreferences(vm.archive.preferences.copy(aiConsentVersion = 1))
        }
        openHistory()
        compose.onNodeWithTag("settings-history-list").performScrollToNode(hasText(history.title))
        compose.onNodeWithText(history.title).performClick()
        compose.onNodeWithText("Switch to the language of this conversation to check its sentences.").assertExists()
        compose.onNodeWithTag("check-correction-${history.passages.single().id}").performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { assertEquals(0, correctionCalls) }
    }

    @Test fun cacheSearchExplicitSaveRetryAndRehearsalUseTheRealScreens() {
        compose.runOnIdle {
            vm.saveKey("synthetic-practice-key")
            vm.updatePreferences(vm.archive.preferences.copy(aiConsentVersion = 1))
        }
        openHistory()
        compose.onNodeWithTag("history-search").performTextInput("visit yesterday")
        compose.onNodeWithText(history.title).performClick()
        compose.onNodeWithTag("history-cached-translation").assertTextContains("My visit yesterday.")
        compose.onNodeWithTag("save-expression").performScrollTo().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Expression saved.").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("save-expression").performScrollTo().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("This expression is already saved.").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("check-correction-${history.passages.single().id}").performScrollTo().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("retry-correction").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("retry-correction").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("save-correction").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Je suis allé hier.").assertExists()
        compose.onNodeWithText("Use the past tense for yesterday.").assertExists()
        compose.runOnIdle { assertTrue(vm.archive.practice!!.corrections.none { it.sourceSessionID == history.id }) }
        compose.onNodeWithTag("save-correction").performScrollTo().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Saved to your correction notebook.").fetchSemanticsNodes().isNotEmpty() }
        closeDialog("practice-correction-dialog")
        closeDialog("history-transcript")
        compose.onNode(hasTestTag("settings-done") and hasAnyAncestor(hasTestTag("settings-history-sheet"))).performClick()
        closeDialog("settings-container") // Back from Learning data.
        closeDialog("settings-container")
        compose.onNodeWithTag("tab-words").performClick()
        compose.onNodeWithTag("open-correction-notebook").performClick()
        val correction = compose.runOnIdle { vm.archive.practice!!.corrections.single { it.sourceSessionID == history.id } }
        compose.onNodeWithTag("correction-${correction.id}").performClick()
        compose.onNodeWithTag("rehearse-correction").performScrollTo().performClick()
        compose.runOnIdle {
            assertTrue(vm.isRunning)
            assertEquals("correction", vm.session?.practiceKind)
            assertEquals("correction", vm.session?.themeID)
            assertEquals(2, correctionCalls)
        }
        compose.onNodeWithTag("daily-practice-open").assertDoesNotExist()
        compose.onNodeWithTag("tab-words").performClick()
        compose.onNodeWithTag("open-correction-notebook").performClick()
        compose.onNodeWithTag("correction-${correction.id}").performClick()
        compose.onNodeWithTag("rehearse-correction").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("delete-correction").performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { vm.end() }
        onMain { vm.correctPassage(history.id, history.passages.single().id, history.passages.single().revisionKey, "Je suis allé avant-hier.") }
        compose.runOnIdle { assertTrue(vm.archive.practice!!.corrections.none { it.id == correction.id }) }
    }

    private fun saveFixtureKeyInModelDialog() {
        compose.onNodeWithTag("api-key-input").performScrollTo().performTextInput("synthetic-practice-key")
        compose.onNodeWithTag("model-config-save").performScrollTo().performClick()
    }

    private fun openHistory() {
        compose.onNodeWithTag("tab-settings").performClick()
        compose.onNodeWithTag("settings-screen").performScrollToNode(hasTestTag("settings-data"))
        compose.onNodeWithTag("settings-data").performClick()
        compose.onNodeWithTag("settings-screen").performScrollToNode(hasTestTag("settings-history"))
        compose.onNodeWithTag("settings-history").performClick()
    }

    private fun closeDialog(tag: String) {
        compose.onNode(hasTestTag("settings-done") and hasAnyAncestor(hasTestTag(tag))).performClick()
    }

    private fun onMain(action: suspend () -> Unit) = runBlocking { withContext(Dispatchers.Main) { action() } }
}
