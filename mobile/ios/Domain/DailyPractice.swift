import Foundation
public struct DailyPracticePlan: Sendable {
    public let languageID: String; public let themeID: String; public let words: [WordState]
    public static func make(languageID: String, words: [WordState], now: Date = .now) -> DailyPracticePlan? {
        guard let theme = LanguageRegistry.module(for: languageID)?.themes.first else { return nil }
        let due = words.filter { $0.id.hasPrefix(languageID + "|") && $0.dueAt <= now }.sorted { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }
        return DailyPracticePlan(languageID: languageID, themeID: theme.id, words: Array(due.prefix(3)))
    }
}

public extension SessionRecord {
    func practiceMinutes(regular: Int) -> Int { practiceKind == "daily" ? 5 : regular }

    func cachedTranslation(for passage: Passage, meaningLanguage: String) -> String? {
        translations[MeaningRequest.cacheKey(revisionKey: passage.revisionKey, language: meaningLanguage)]
            ?? translations[meaningLanguage + "::" + passage.revisionKey] ?? translations[passage.revisionKey]
    }
}
