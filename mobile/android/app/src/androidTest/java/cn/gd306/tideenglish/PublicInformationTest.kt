package cn.gd306.tideenglish

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import cn.gd306.tideenglish.ui.InterfaceLanguage
import cn.gd306.tideenglish.ui.LocalInterfaceLanguage
import cn.gd306.tideenglish.ui.PublicInformationLink
import cn.gd306.tideenglish.ui.PublicInformationPage
import cn.gd306.tideenglish.ui.TideEnglishTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class PublicInformationTest {
    @get:Rule val compose = createComposeRule()

    private fun verifyLocalPage(page: PublicInformationPage, language: InterfaceLanguage, title: String, heading: String) {
        val opened = mutableListOf<String>()
        val uri = object : UriHandler { override fun openUri(uri: String) { opened += uri } }
        compose.setContent {
            CompositionLocalProvider(LocalUriHandler provides uri, LocalInterfaceLanguage provides language) {
                TideEnglishTheme { PublicInformationLink(page) }
            }
        }
        compose.onNodeWithText(title).performClick()
        compose.onNodeWithTag("public-information-${page.key}").assertExists()
        compose.onNodeWithText(heading).assertExists()
        compose.runOnIdle { assertTrue(opened.isEmpty()) }
        compose.onNodeWithTag("public-information-close").performClick()
        compose.onNodeWithText(title).assertIsDisplayed()
    }

    @Test fun draftPrivacyOpensReadableChineseWithoutBrowser() =
        verifyLocalPage(PublicInformationPage.PRIVACY, InterfaceLanguage.CHINESE, "隐私政策", "保存在设备上")

    @Test fun draftSupportOpensReadableEnglishWithoutBrowser() =
        verifyLocalPage(PublicInformationPage.SUPPORT, InterfaceLanguage.ENGLISH, "Contact support", "Start a conversation")
}
