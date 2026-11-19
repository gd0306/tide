import Foundation
import SwiftData
import Security
import Observation
import TideEnglishCore

@Model final class StoredArchive {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { key = "tideenglish-v1"; self.payload = payload }
}

@MainActor @Observable final class LearningStore {
    private(set) var archive = Archive() { didSet { projectionRevision &+= 1 } }
    @ObservationIgnored private var projectionRevision = 0
    @ObservationIgnored private var cachedProjection: (Int, LearnerState)?
    private(set) var finalAssessmentTickets: [FinalAssessmentTicket] = []
    var error: String?
    @ObservationIgnored var onSessionInvalidation: ((UUID) -> Void)?
    @ObservationIgnored var onVocabularyContextChange: (() -> Void)?
    @ObservationIgnored var onVocabularyErase: (() -> Void)?
    @ObservationIgnored private(set) var vocabularyCache = VocabularyCache()
    private(set) var vocabularyCacheError: String?
    private let vocabularyCacheURL: URL?
    let container: ModelContainer
    private var document: StoredArchive
    private let migrationBackupURL: URL?
    static var supportDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Tide English", isDirectory: true)
    }
    init(inMemory: Bool = false) throws {
        vocabularyCacheURL = inMemory ? nil : URL.applicationSupportDirectory
            // Keep the original directory so a brand update preserves existing learning data.
            .appendingPathComponent("Tide English", isDirectory: true)
            .appendingPathComponent("vocabulary-definitions-v1.json")
        migrationBackupURL = inMemory ? nil : Self.supportDirectory
            .appendingPathComponent("before-language-modules.json")
        if !inMemory {
            try ArchiveDeletionTransaction.recoverPending(files: [migrationBackupURL, vocabularyCacheURL].compactMap { $0 },
                stagingRoot: Self.supportDirectory.appendingPathComponent("pending-deletions", isDirectory: true))
        }
        if let url = vocabularyCacheURL,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= 4 * 1024 * 1024,
           let data = try? Data(contentsOf: url), let cache = try? VocabularyCache.decode(data) {
            vocabularyCache = cache
        }
        var configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        #if DEBUG && targetEnvironment(simulator)
        if inMemory, ProcessInfo.processInfo.arguments.contains("--preview-practice"),
           let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--practice-store=") }),
           let id = UUID(uuidString: String(arg.dropFirst("--practice-store=".count))) {
            configuration = ModelConfiguration(url: URL.temporaryDirectory.appendingPathComponent("practice-\(id).store"), cloudKitDatabase: .none)
        }
        #endif
        container = try ModelContainer(for: StoredArchive.self, configurations: configuration)
        let context = container.mainContext
        if let existing = try context.fetch(FetchDescriptor<StoredArchive>()).first {
            document = existing
            archive = try Archive.decode(existing.payload)
            if let root = try JSONSerialization.jsonObject(with: existing.payload) as? [String: Any], let metadata = root["iosFinalAssessments"] {
                let bytes = try JSONSerialization.data(withJSONObject: metadata)
                finalAssessmentTickets = try JSONDecoder().decode([FinalAssessmentTicket].self, from: bytes)
                guard finalAssessmentTickets.count <= 10_000, finalAssessmentTickets.allSatisfy({ (0...3).contains($0.attempts) }) else { throw ArchiveError.invalid }
            }
            if let backup = migrationBackupURL,
               let root = try JSONSerialization.jsonObject(with: existing.payload) as? [String: Any], root["schemaVersion"] as? Int == 1 {
                let directory = backup.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try existing.payload.write(to: backup, options: [.atomic, .completeFileProtection])
                }
            }
            for i in archive.sessions.indices where archive.sessions[i].endedAt == nil {
                archive.sessions[i].endedAt = .now; archive.sessions[i].endReason = "App closed before finalization"
            }
        } else {
            document = StoredArchive(payload: try Archive().encoded()); context.insert(document)
        }
        try commit(archive, tickets: finalAssessmentTickets)
    }
    var preferences: Preferences { archive.preferences }
    var language: LanguageModule { LanguageRegistry.module(for: preferences.learningLanguageID)! }
    var sessions: [SessionRecord] { archive.sessions.sorted { $0.startedAt > $1.startedAt } }
    var learningSessions: [SessionRecord] { sessions.filter { $0.languageID == language.id } }
    var learner: LearnerState {
        if let cachedProjection, cachedProjection.0 == projectionRevision { return cachedProjection.1 }
        let value = LearningEngine.project(archive.sessions, languageID: language.id, hiddenWords: archive.preferences.hiddenWords)
        cachedProjection = (projectionRevision, value)
        return value
    }
    func selectLanguage(_ id: String) {
        guard LanguageRegistry.module(for: id) != nil else { return }
        archive.preferences.learningLanguageID = id; persist()
    }
    func updatePreferences(_ change: (inout Preferences) -> Void) { change(&archive.preferences); persist() }
    func save(_ session: SessionRecord) {
        if let i = archive.sessions.firstIndex(where: { $0.id == session.id }) { archive.sessions[i] = session }
        else { archive.sessions.append(session) }
        persist()
    }
    func deleteSession(_ id: UUID) {
        var candidate = archive
        candidate.sessions.removeAll { $0.id == id }
        candidate.practice?.corrections.removeAll { $0.sourceSessionID == id }
        do {
            try commit(candidate, tickets: finalAssessmentTickets.filter { $0.sessionID != id })
            onSessionInvalidation?(id)
        } catch { self.error = "Tide couldn’t save your progress. Please export a backup and try again." }
    }
    func hideWord(_ id: String) { archive.preferences.hiddenWords.append(id); persist() }
    func correctPassage(sessionID: UUID, passageID: String, text: String) {
        var candidate = archive
        guard let index = candidate.sessions.firstIndex(where: { $0.id == sessionID }),
              candidate.sessions[index].endedAt != nil,
              let passage = candidate.sessions[index].passages.first(where: { $0.id == passageID && $0.speaker == .user }) else { return }
        for (offset, fragment) in passage.fragments.enumerated() {
            candidate.sessions[index].correctFragment(id: fragment.id, text: offset == 0 ? String(text.prefix(10_000)) : "")
        }
        candidate.practice?.invalidateCorrections(sessions: candidate.sessions)
        do {
            try commit(candidate, tickets: finalAssessmentTickets.filter { $0.sessionID != sessionID })
            onSessionInvalidation?(sessionID)
        } catch { self.error = "Tide couldn’t save your progress. Please export a backup and try again." }
    }
    var practice: PracticeLibrary { archive.practice ?? PracticeLibrary() }
    func saveExpression(_ value: SavedExpression) throws -> Bool {
        var library = practice
        let saved = try library.saveExpression(value)
        guard !practice.expressions.contains(where: { $0.id == saved.id }) else { return false }
        try savePractice(library)
        return true
    }
    func saveCorrection(_ value: SavedCorrection) throws {
        var library = practice
        guard try library.saveCorrection(value, sessions: archive.sessions) else { throw ArchiveError.invalid }
        try savePractice(library)
    }
    func deleteExpression(_ id: UUID) throws {
        var library = practice
        library.deleteExpression(id: id)
        try savePractice(library)
    }
    func deleteCorrection(_ id: UUID) throws {
        var library = practice
        library.deleteCorrection(id: id)
        try savePractice(library)
    }
    private func savePractice(_ library: PracticeLibrary) throws {
        var candidate = archive
        candidate.practice = library
        try commit(candidate, tickets: finalAssessmentTickets)
    }
    func deleteAll() {
        let ids = archive.sessions.map(\.id)
        var candidate = archive
        candidate.sessions = []; candidate.preferences.hiddenWords = []; candidate.practice = nil
        var committed = false
        do {
            let files = [migrationBackupURL, vocabularyCacheURL].compactMap { $0 }
            if files.isEmpty {
                try commit(candidate, tickets: []); committed = true
            } else {
                try ArchiveDeletionTransaction.run(files: files, stagingRoot: Self.supportDirectory.appendingPathComponent("pending-deletions", isDirectory: true)) {
                    try commit(candidate, tickets: [])
                    committed = true
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        if committed {
            ids.forEach { onSessionInvalidation?($0) }
            vocabularyCache.removeAll(); vocabularyCacheError = nil
            onVocabularyErase?()
        }
    }
    func exportData() throws -> Data { try archive.encoded() }
    func importData(_ data: Data) throws {
        var transaction = ArchiveImportTransaction(archive: archive)
        try transaction.importData(data) { payload in
            let previous = document.payload
            document.payload = try storedPayload(archiveData: payload, tickets: finalAssessmentTickets)
            do { try container.mainContext.save() }
            catch { document.payload = previous; throw error }
        }
        archive = transaction.archive
        error = nil
        onVocabularyContextChange?()
    }
    func saveVocabularyCache(_ cache: VocabularyCache) {
        vocabularyCache = cache
        guard let url = vocabularyCacheURL else { return }
        do {
            try ArchiveDeletionTransaction.recoverPending(files: [migrationBackupURL, vocabularyCacheURL].compactMap { $0 },
                stagingRoot: Self.supportDirectory.appendingPathComponent("pending-deletions", isDirectory: true))
            let data = try cache.encoded()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            vocabularyCacheError = nil
        } catch {
            vocabularyCacheError = "Definitions are available now but couldn’t be saved for next time."
        }
    }
    private func storedPayload(archiveData: Data, tickets: [FinalAssessmentTicket]) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: archiveData) as? [String: Any] else { throw ArchiveError.invalid }
        root["iosFinalAssessments"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tickets))
        let data = try JSONSerialization.data(withJSONObject: root)
        guard data.count <= Archive.maximumEncodedBytes else { throw ArchiveError.tooLarge }
        return data
    }
    private func commit(_ candidate: Archive, tickets: [FinalAssessmentTicket]) throws {
        let payload = try storedPayload(archiveData: candidate.encoded(), tickets: tickets)
        let previous = document.payload
        document.payload = payload
        do { try container.mainContext.save() }
        catch { document.payload = previous; throw error }
        archive = candidate; finalAssessmentTickets = tickets; error = nil
        onVocabularyContextChange?()
    }
    func saveForFinalAssessment(_ session: SessionRecord, provider: String) throws {
        var candidate = archive
        if let index = candidate.sessions.firstIndex(where: { $0.id == session.id }) { candidate.sessions[index] = session }
        else { candidate.sessions.append(session) }
        try commit(candidate, tickets: FinalAssessmentRecovery.enqueue(session, provider: provider, tickets: finalAssessmentTickets))
    }
    func beginFinalAssessment(_ session: SessionRecord, provider: String) throws -> Bool {
        guard FinalAssessmentRecovery.recover([session], tickets: finalAssessmentTickets, provider: provider, consent: true).contains(where: { $0.id == session.id }),
              let index = finalAssessmentTickets.firstIndex(where: { $0.sessionID == session.id }) else { return false }
        var tickets = finalAssessmentTickets; tickets[index].attempts += 1
        try commit(archive, tickets: tickets)
        return true
    }
    func finishFinalAssessment(_ session: SessionRecord) throws {
        var candidate = archive
        guard let index = candidate.sessions.firstIndex(where: { $0.id == session.id }) else { return }
        candidate.sessions[index] = session
        try commit(candidate, tickets: finalAssessmentTickets.filter { $0.sessionID != session.id })
    }
    func discardFinalAssessments() {
        do { try commit(archive, tickets: []) }
        catch { self.error = "Tide couldn’t save your progress. Please export a backup and try again." }
    }
    private func persist() {
        onVocabularyContextChange?()
        do { document.payload = try storedPayload(archiveData: archive.encoded(), tickets: finalAssessmentTickets); try container.mainContext.save(); error = nil }
        catch { self.error = "Tide couldn’t save your progress. Please export a backup and try again." }
    }
}

/// Recovery opens the existing store without decoding or replacing its payload.
@MainActor enum StartupArchiveRecovery {
    static func readRaw() throws -> Data {
        let container = try ModelContainer(for: StoredArchive.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
        guard let document = try container.mainContext.fetch(FetchDescriptor<StoredArchive>()).first else { throw ArchiveError.invalid }
        return try ArchiveRecoveryExport.sanitized(document.payload)
    }
    static func restore(_ data: Data) throws {
        let sanitized = try Archive.decode(data).encoded()
        let container = try ModelContainer(for: StoredArchive.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
        guard let document = try container.mainContext.fetch(FetchDescriptor<StoredArchive>()).first else { throw ArchiveError.invalid }
        let directory = LearningStore.supportDirectory.appendingPathComponent("recovery-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try document.payload.write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: [.atomic, .completeFileProtection])
        let previous = document.payload
        document.payload = sanitized
        do { try container.mainContext.save() }
        catch { document.payload = previous; throw error }
    }
}

enum CredentialStore {
    private static func query(configuration: ProviderConfiguration) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: try configuration.credentialService(),
         kSecAttrAccount as String: "owner", kSecAttrSynchronizable as String: false]
    }
    // Legacy methods retain the installed OpenAI service/account.
    static func read() -> String? { read(configuration: .init(provider: .openAI)) }
    static var hasKey: Bool { hasKey(configuration: .init(provider: .openAI)) }
    static func save(_ key: String) throws { try save(key, configuration: .init(provider: .openAI)) }
    static func delete() throws { try delete(configuration: .init(provider: .openAI)) }
    static func read(configuration: ProviderConfiguration) -> String? {
        guard var q = try? query(configuration: configuration) else { return nil }
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func hasKey(configuration: ProviderConfiguration) -> Bool {
        guard var q = try? query(configuration: configuration) else { return false }
        // Presence must never retrieve or decode the secret.
        q[kSecReturnAttributes as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
    static func save(_ key: String, configuration: ProviderConfiguration) throws {
        let value = try ProviderConfiguration.validatedCredential(key)
        let q = try query(configuration: configuration)
        let data = Data(value.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw KeyError.save }
        } else if status != errSecSuccess { throw KeyError.save }
    }
    static func delete(configuration: ProviderConfiguration) throws {
        let status = SecItemDelete(try query(configuration: configuration) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.remove }
    }
    enum KeyError: LocalizedError {
        case invalid, save, remove
        var errorDescription: String? {
            switch self {
            case .invalid: "Enter a valid API key."
            case .save: "The key couldn’t be saved to this device’s Keychain."
            case .remove: "The key couldn’t be removed. Unlock this iPhone and try again."
            }
        }
    }
}
