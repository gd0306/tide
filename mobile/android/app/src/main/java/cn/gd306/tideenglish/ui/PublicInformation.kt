package cn.gd306.tideenglish.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import cn.gd306.tideenglish.core.readPublicInformation
import cn.gd306.tideenglish.core.PublicMetadata
import cn.gd306.tideenglish.core.isPublicHttpsURL

internal enum class PublicInformationPage(val key: String) {
    PRIVACY("privacy"), SUPPORT("support"), TERMS("terms");

    @Composable fun title(): String = when (this) {
        PRIVACY -> uiText("Privacy policy", "隐私政策")
        SUPPORT -> uiText("Contact support", "帮助与支持")
        TERMS -> uiText("Terms of use", "使用条款")
    }
}

/** A click remains useful offline while the configured website awaits publication. */
@Composable
internal fun rememberPublicInformationOpener(): (PublicInformationPage) -> Unit {
    var pageKey by rememberSaveable { mutableStateOf<String?>(null) }
    PublicInformationPage.entries.firstOrNull { it.key == pageKey }?.let { page ->
        PublicInformationDialog(page) { pageKey = null }
    }
    return { pageKey = it.key }
}

@Composable
internal fun PublicInformationLink(page: PublicInformationPage, modifier: Modifier = Modifier) {
    val open = rememberPublicInformationOpener()
    TideEnglishTextButton(onClick = { open(page) }, modifier = modifier.heightIn(min = 48.dp)) {
        Text(page.title())
    }
}

@Composable
private fun bundledPublicMetadata(): PublicMetadata? {
    val context = LocalContext.current
    return remember(context) { PublicMetadata.decode(readPublicInformation(context)) }
}

@Composable
internal fun PublicInformationDialog(page: PublicInformationPage, info: PublicMetadata? = bundledPublicMetadata(), onDismiss: () -> Unit) {
    val uri = LocalUriHandler.current
    var openingFailed by rememberSaveable(page) { mutableStateOf(false) }
    val website = info?.takeIf { it.publicPagesReady }?.links?.get(page.key)?.takeIf(::isPublicHttpsURL)
    val sections = when (page) {
        PublicInformationPage.PRIVACY -> listOf(
            uiText("On this device", "保存在设备上") to uiText("Conversations, vocabulary, translations and saved practice stay in the app’s local storage. API keys are kept separately in system secure storage and excluded from learning backups. System backups depend on device settings.", "对话、词汇、译文和保存的练习保存在应用本机存储中。API Key 独立保存在系统安全存储中，不包含在学习备份里。系统备份还受设备设置影响。"),
            uiText("When you use AI", "使用 AI 时") to uiText("After your consent, selected text and necessary learning context go to your chosen model provider. Native realtime voice also sends microphone audio. Device voice uses on-device recognition where supported, then sends recognized text. Provider retention, region and billing rules apply. Tide does not save raw microphone recordings.", "经你同意后，选中的文字与必要学习上下文会发送给所选模型服务商。原生实时语音也会发送麦克风音频。设备语音在支持时使用本机识别，再发送识别文字。服务商的数据保留、地区与计费规则适用。潮语不保存原始麦克风录音。"),
            uiText("Your choices", "由你决定") to uiText("Refusing AI still lets you read saved content. Withdraw consent in Settings to stop new requests. Delete conversations or all learning data in Learning data. Exported files are separate copies you must manage yourself.", "拒绝 AI 处理后仍可查看已存内容。在设置中撤回同意可停止后续请求。在学习数据中可删除对话或全部记录。主动导出的文件是独立副本，需自行管理。"),
            uiText("Current service", "当前服务方式") to uiText("This personal-key version is for adults. Accounts, hosted conversations, purchases and learning sync are disabled by default. Microphone and speech permissions are for practice you start.", "个人 Key 版本面向成年人。账户、托管对话、内购和学习同步默认关闭。麦克风与语音识别权限用于你主动开始的练习。")
        )
        PublicInformationPage.SUPPORT -> listOf(
            uiText("Start a conversation", "开始练习") to uiText("Choose your learning and meaning languages, then save your own API key in Model settings. Text and realtime voice models have different capabilities and account requirements. Requests may incur provider charges.", "选择学习与释义语言，然后在模型设置中保存自己的 API Key。文本与实时语音模型的能力、账户权限不同，请求可能产生服务商费用。"),
            uiText("Connection and voice", "连接与语音") to uiText("Check the key, provider, endpoint, model and provider quota. If on-device speech is unavailable, use text. After network or headphone changes, check conversation state before retrying.", "检查 Key、服务商、请求地址、模型与账户额度。本机语音不可用时可使用文字。网络或耳机切换后先检查会话状态再重试。"),
            uiText("Protect your learning", "保护学习记录") to uiText("Export backups in Learning data regularly. Avoid uninstalling Tide to troubleshoot. On read errors, preserve the original file and use Retry or Restore from backup. Review backups before sharing.", "定期在学习数据中导出备份，排查问题时避免卸载潮语。遇到读取错误请保留原文件，使用重试或从备份恢复。分享备份前请检查内容。"),
            uiText("Report a problem", "反馈问题") to uiText("Include app/system versions, provider, error and steps to reproduce. Never post API keys, codes or full private archives. Project issues are public.", "请提供应用与系统版本、服务商、错误提示和复现步骤。不要提交 API Key、验证码或完整私人档案。项目问题页面是公开的。")
        )
        PublicInformationPage.TERMS -> listOf(
            uiText("Practice and AI", "练习与 AI") to uiText("Tide provides language practice for adults. AI translations and corrections may be wrong. Results are guidance, not formal language or exam certification.", "潮语为成年人提供语言练习。AI 翻译与纠错可能不准确，结果是辅助建议，不构成正式语言等级或考试认证。"),
            uiText("Your model account", "你的模型账户") to uiText("Use only keys and accounts you are authorized to use. Follow provider terms, regions and billing rules; do not share keys. Use the app lawfully and submit content you have the right to use.", "仅使用你有权使用的 Key 与账户，遵守服务商条款、地区和计费规则，不分享密钥。请合法使用应用，仅提交你有权使用的内容。"),
            uiText("Software and data", "软件与数据") to uiText("The source uses the project’s MIT license; third-party licenses remain in Open-source notices. Model services and charges are separate. Keep backups safe and review feedback before sharing.", "源码遵循项目 MIT 许可，第三方组件适用开源声明中的各自许可。模型服务与费用另行适用。请妥善保管备份，分享反馈前检查内容。")
        )
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(page.title()) },
        text = {
            SelectionContainer {
                Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).testTag("public-information-${page.key}"),
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    sections.forEach { (sectionHeading, content) ->
                        Text(sectionHeading, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                        Text(content, style = MaterialTheme.typography.bodyLarge)
                    }
                    listOfNotNull(info?.publisherName, info?.supportEmail, info?.appFilingNumber).forEach { value ->
                        if (value.isNotBlank()) Text(value)
                    }
                    if (page == PublicInformationPage.SUPPORT || website != null) {
                        TideEnglishTextButton(onClick = {
                            openingFailed = runCatching { uri.openUri(website ?: "https://github.com/gd0306/tide/issues") }.isFailure
                        }) { Text(if (website != null) uiText("Read on website", "在网站查看") else uiText("Project issues (public)", "项目问题页面（公开）")) }
                    }
                    if (openingFailed) Text(uiText("Could not open a browser. You can still read this page here.", "无法打开浏览器，你仍可在这里阅读说明。"))
                }
            }
        },
        confirmButton = {
            TideEnglishTextButton(onClick = onDismiss, modifier = Modifier.testTag("public-information-close")) {
                Text(uiText("Close", "关闭"))
            }
        }
    )
}
