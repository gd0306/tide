package cn.gd306.tideenglish

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import cn.gd306.tideenglish.core.CorrectionSource
import cn.gd306.tideenglish.core.CorrectionState
import cn.gd306.tideenglish.core.SavedCorrection
import cn.gd306.tideenglish.ui.PracticeCorrectionDialog
import cn.gd306.tideenglish.ui.TideEnglishTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class LargeTypePracticeTest {
    @get:Rule val compose = createComposeRule()

    @Test fun longCorrectionKeepsSaveReachableAtDoubleTextSize() {
        val original = "Quand je parle de mon voyage, je vais hier au marché. ".repeat(18)
        val suggestion = "Je suis allé au marché hier."
        val explanation = "Utilisez le passé composé pour raconter ce qui est arrivé hier. ".repeat(22)
        val source = CorrectionSource(UUID.randomUUID().toString(), "passage", "passage:0", original, "fr")
        val correction = SavedCorrection(languageID = source.languageID, original = original, corrected = suggestion,
            explanation = explanation, sourceSessionID = source.sessionID, sourcePassageID = source.passageID,
            revisionKey = source.revisionKey)
        var saves = 0
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, 2f)) {
                TideEnglishTheme {
                    PracticeCorrectionDialog(CorrectionState.Answer(source, correction), running = false, onRetry = {},
                        onSave = { saves++ }, onModelSetup = {}, onDismiss = {})
                }
            }
        }
        compose.onNodeWithText(original).assertExists()
        compose.onNodeWithText(explanation).performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("save-correction").performScrollTo().assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals(1, saves) }
    }
}
