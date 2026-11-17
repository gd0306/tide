import SwiftUI
import TideEnglishCore

@main struct TideEnglishApp: App {
    @State private var store: LearningStore?
    @State private var startupError: String?
    @State private var startupBackup: BackupDocument?
    @State private var exportingStartup = false
    @State private var importingStartup = false
    #if DEBUG
    @State private var echoStatus = "Checking echo cancellation"
    #endif
    init() {
        do { _store = State(initialValue: try LearningStore(inMemory: ProcessInfo.processInfo.arguments.contains("--preview") || AudioVerification.requested)) }
        catch { _startupError = State(initialValue: "Tide couldn’t open its learning record. Your existing data has not been replaced.") }
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if AudioVerification.echoRequested {
                Text(echoStatus).accessibilityIdentifier("echo-check-status")
                    .task {
                        echoStatus = ProcessInfo.processInfo.arguments.contains("--verify-input")
                            ? await AudioVerification.verifyInput() : await AudioVerification.verifyEcho()
                    }
            } else if AudioVerification.providerRequested {
                ContentUnavailableView(UI("Checking Gemini"), systemImage: "antenna.radiowaves.left.and.right", description: Text(UI("A short connection check is running. No microphone audio is captured.")))
                    .task { await AudioVerification.verifyProvider(configuration: ModelSettings.configuration(for: .gemini)) }
            } else { content }
            #else
            content
            #endif
        }
    }
    private func retryStartup() {
        do { store = try LearningStore(); startupError = nil }
        catch { startupError = "Tide couldn’t open its learning record. Your existing data has not been replaced." }
    }
    @ViewBuilder private var content: some View {
            if let store { RootView(store: store).modifier(InterfaceAppearance()) }
            else {
                VStack(spacing: 16) {
                    ContentUnavailableView(UI("Let’s try again"), systemImage: "externaldrive.badge.exclamationmark", description: Text(UI(startupError ?? "The learning record is unavailable.")))
                    Button(UI("Try again")) { retryStartup() }
                    Button(UI("Export original learning record")) {
                        do { startupBackup = BackupDocument(data: try StartupArchiveRecovery.readRaw()); exportingStartup = true }
                        catch { startupError = error.localizedDescription }
                    }
                    Button(UI("Restore from backup")) { importingStartup = true }
                }
                .fileExporter(isPresented: $exportingStartup, document: startupBackup, contentType: .json, defaultFilename: "Tide-original-record") { result in
                    if case .failure(let error) = result { startupError = error.localizedDescription }
                }
                .fileImporter(isPresented: $importingStartup, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        try StartupArchiveRecovery.restore(Archive.readImportData(from: url))
                        retryStartup()
                    } catch { startupError = error.localizedDescription }
                }
                .modifier(InterfaceAppearance())
            }
    }
}

/// Observe presentation below the coordinator-construction boundary. SwiftUI can
/// reevaluate this modifier without calling RootView.init or replacing the
/// learning store's session-invalidation callback with a discarded coordinator.
private struct InterfaceAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(InterfacePreferences.shared.colorScheme)
            .environment(\.locale, InterfacePreferences.shared.locale)
    }
}
