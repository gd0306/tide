import SwiftUI
import TideEnglishCore

enum PublicInformationPage: String {
    case privacy, support, terms

    @MainActor var title: String {
        switch self {
        case .privacy: UI("Privacy policy")
        case .support: UI("Contact support")
        case .terms: UI("Terms of use")
        }
    }
}

private struct PublicInformation: Decodable {
    let schemaVersion: Int
    let publisherName: String
    let supportEmail: String
    let publicPagesReady: Bool
    let links: [String: String]
    let appFilingNumber: String

    static let bundled: Self? = Bundle.main.url(forResource: "PublicInformation", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Self.self, from: $0) }

    func url(for page: PublicInformationPage) -> URL? {
        guard schemaVersion == 1, publicPagesReady, let value = links[page.rawValue],
              let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host, !host.isEmpty, !host.hasSuffix(".example") else { return nil }
        return url
    }
}

/// A draft build always has a readable, offline explanation instead of a dead URL.
struct PublicInformationLink: View {
    let page: PublicInformationPage
    @State private var showingLocal = false

    var body: some View {
        Group {
            if let url = PublicInformation.bundled?.url(for: page) {
                Link(page.title, destination: url)
            } else {
                Button(page.title) { showingLocal = true }
            }
        }
        .frame(minHeight: 44)
        .sheet(isPresented: $showingLocal) {
            PublicInformationView(page: page)
        }
    }
}

private struct PublicInformationView: View {
    let page: PublicInformationPage
    @Environment(\.dismiss) private var dismiss

    private func copy(_ english: String, _ chinese: String) -> String {
        InterfacePreferences.shared.language == .chinese ? chinese : english
    }

    private var sections: [(String, String)] {
        switch page {
        case .privacy:
            return [
                (copy("On this device", "保存在设备上"), copy("Conversations, vocabulary, translations and saved practice stay in the app’s local storage. Your model API keys are stored separately in system secure storage and are excluded from learning backups. System backups depend on your device settings.", "对话、词汇、译文和保存的练习保存在应用本机存储中。模型 API Key 独立保存在系统安全存储中，不包含在学习备份里。系统备份还受设备设置影响。")),
                (copy("When you use AI", "使用 AI 时"), copy("After your consent, selected text and necessary learning context go to your chosen model provider. Native realtime voice sends microphone audio to that provider. Device voice uses on-device recognition when supported and sends recognized text. The provider’s retention, region and billing rules apply. Tide does not save raw microphone recordings.", "经你同意后，选中的文字与必要学习上下文会发送给所选模型服务商。原生实时语音也会发送麦克风音频；设备语音在支持时使用本机识别，再发送识别文字。服务商的数据保留、地区与计费规则适用。潮语不保存原始麦克风录音。")),
                (copy("Your choices", "由你决定"), copy("You can refuse AI processing and still read saved content. Withdraw consent in Settings to stop further requests. Delete conversations or all learning data in Learning data. Exported files must be managed separately; deleting inside Tide does not delete copies you exported.", "你可以拒绝 AI 处理并继续查看已存内容。在设置中撤回同意可停止后续请求；在学习数据中可删除对话或全部学习记录。主动导出的文件需自行管理，应用内删除不会删除这些外部副本。")),
                (copy("Current service", "当前服务方式"), copy("This personal-key version is for adults. In-app accounts, hosted conversations, purchases and learning sync are disabled by default. Microphone and speech permissions are requested for practice you start.", "个人 Key 版本面向成年人。应用内账户、托管对话、内购和学习同步默认关闭。麦克风和语音识别权限用于你主动开始的练习。"))
            ]
        case .support:
            return [
                (copy("Start a conversation", "开始练习"), copy("Choose your learning and meaning languages, then select a provider in Model settings and save your own API key. Text models and native realtime voice have different capabilities and account requirements. Starting AI requests may incur provider charges.", "选择学习与释义语言，然后在模型设置中选择服务商并保存自己的 API Key。文本模型和原生实时语音的能力、账户权限不同，发起 AI 请求可能产生服务商费用。")),
                (copy("Connection and voice", "连接与语音"), copy("Check that your key, provider, endpoint and model match, and that the provider account has quota. If on-device speech is unavailable, use text. After a network interruption or headphone change, check the conversation state before retrying.", "检查 Key、服务商、请求地址与模型是否匹配，以及服务商账户是否有可用额度。本机语音不可用时可使用文字。网络中断或耳机切换后，先检查会话状态再重试。")),
                (copy("Protect your learning", "保护学习记录"), copy("Export a backup from Learning data regularly. Avoid uninstalling Tide to troubleshoot. On a read error, keep the original file and use Retry or Restore from backup. Backups contain learning content; review files before sharing.", "定期在学习数据中导出备份。排查问题时避免卸载潮语。遇到读取错误请保留原文件，使用重试或从备份恢复。备份包含学习内容，分享前请自行检查。")),
                (copy("Report a problem", "反馈问题"), copy("Include the app and system versions, provider, error and reproduction steps. Never post API keys, codes or a full private archive. The project issue page is public.", "请提供应用与系统版本、服务商、错误提示及复现步骤。不要提交 API Key、验证码或完整私人档案。项目问题页面是公开的。"))
            ]
        case .terms:
            return [
                (copy("Practice and AI", "练习与 AI"), copy("Tide provides language practice and study aids for adults. AI translations and corrections can be wrong. Practice results are guidance, not formal language or exam certification.", "潮语为成年人提供语言练习与学习辅助。AI 翻译和纠错可能不准确，练习结果是辅助建议，不构成正式语言等级或考试认证。")),
                (copy("Your model account", "你的模型账户"), copy("Use only keys and provider accounts you are authorized to use. Follow the provider’s terms, regional availability and billing rules. Do not share secret keys. Use the app lawfully and submit only content you have the right to use.", "仅使用你有权使用的 Key 与服务商账户，遵守其条款、服务地区和计费规则，不分享密钥。请合法使用应用，并仅提交你有权使用的内容。")),
                (copy("Software and data", "软件与数据"), copy("The source code uses the project’s MIT license; third-party components retain their own licenses in Open-source notices. Provider services and charges are separate. Keep your backups safe and review feedback before sharing it.", "源码遵循项目 MIT 许可，第三方组件适用开源声明中的各自许可。模型服务与费用另行适用。请妥善保管备份，并在提交反馈前检查内容。"))
            ]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    Section(section.0) { Text(section.1).textSelection(.enabled) }
                }
                if page == .support {
                    Section {
                        Link(copy("Open project issues (public)", "打开项目问题页面（公开）"), destination: URL(string: "https://github.com/gd0306/tide/issues")!)
                    }
                }
                if let info = PublicInformation.bundled, info.schemaVersion == 1,
                   !info.publisherName.isEmpty || !info.supportEmail.isEmpty || !info.appFilingNumber.isEmpty {
                    Section {
                        if !info.publisherName.isEmpty { Text(info.publisherName) }
                        if !info.supportEmail.isEmpty { Text(info.supportEmail).textSelection(.enabled) }
                        if !info.appFilingNumber.isEmpty { Text(info.appFilingNumber).textSelection(.enabled) }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(TideEnglishColor.cream)
            .foregroundStyle(TideEnglishColor.ink).tint(TideEnglishColor.accent)
            .navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("public-information-\(page.rawValue)")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(UI("Done")) { dismiss() }.accessibilityIdentifier("public-information-close")
            } }
        }.interactiveDismissDisabled(false)
    }
}
