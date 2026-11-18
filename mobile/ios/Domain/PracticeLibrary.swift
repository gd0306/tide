import Foundation

public struct SavedExpression: Codable, Identifiable, Sendable {
    public var id: UUID; public var languageID: String; public var text: String; public var meaning: String; public var context: String
    public var createdAt: Date; public var sourceSessionID: UUID?; public var sourcePassageID: String?; public var revisionKey: String?
    public init(id: UUID = UUID(), languageID: String, text: String, meaning: String, context: String, createdAt: Date = .now, sourceSessionID: UUID? = nil, sourcePassageID: String? = nil, revisionKey: String? = nil) {
        self.id = id; self.languageID = languageID; self.text = text; self.meaning = meaning; self.context = context; self.createdAt = createdAt; self.sourceSessionID = sourceSessionID; self.sourcePassageID = sourcePassageID; self.revisionKey = revisionKey
    }
}
public struct SavedCorrection: Codable, Identifiable, Sendable {
    public var id: UUID; public var languageID: String; public var original: String; public var corrected: String; public var explanation: String
    public var createdAt: Date; public var sourceSessionID: UUID; public var sourcePassageID: String; public var revisionKey: String; public var rehearsedAt: Date?
    public init(id: UUID = UUID(), languageID: String, original: String, corrected: String, explanation: String, createdAt: Date = .now, sourceSessionID: UUID, sourcePassageID: String, revisionKey: String, rehearsedAt: Date? = nil) {
        self.id = id; self.languageID = languageID; self.original = original; self.corrected = corrected; self.explanation = explanation; self.createdAt = createdAt; self.sourceSessionID = sourceSessionID; self.sourcePassageID = sourcePassageID; self.revisionKey = revisionKey; self.rehearsedAt = rehearsedAt
    }
    public func matches(sessions: [SessionRecord]) -> Bool {
        guard let s = sessions.first(where: { $0.id == sourceSessionID && $0.languageID == languageID }), let p = s.passages.first(where: { $0.id == sourcePassageID && $0.speaker == .user }) else { return false }
        return p.revisionKey == revisionKey && p.text == original
    }
}
public struct PracticeLibrary: Codable, Sendable {
    public var expressions: [SavedExpression]; public var corrections: [SavedCorrection]
    public init(expressions: [SavedExpression] = [], corrections: [SavedCorrection] = []) { self.expressions = expressions; self.corrections = corrections }
    // Unicode White_Space, explicitly shared with Android (not Foundation's broader set).
    private static let whitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{0085}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}")
    private func normalized(_ text: String) -> String { text.trimmingCharacters(in: Self.whitespace).precomposedStringWithCanonicalMapping.lowercased() }
    public mutating func saveExpression(_ value: SavedExpression) throws -> SavedExpression {
        try PracticeLibrary(expressions: [value]).validate()
        if let existing = expressions.first(where: { $0.languageID == value.languageID && normalized($0.text) == normalized(value.text) }) { return existing }
        var candidate = self; candidate.expressions.append(value); try candidate.validate(); self = candidate; return value
    }
    @discardableResult public mutating func saveCorrection(_ value: SavedCorrection, sessions: [SessionRecord]) throws -> Bool {
        guard value.matches(sessions: sessions) else { return false }
        if corrections.contains(where: { $0.id == value.id }) { return false }
        var candidate = self; candidate.corrections.append(value); try candidate.validate(); self = candidate; return true
    }
    public mutating func deleteExpression(id: UUID) { expressions.removeAll { $0.id == id } }
    public mutating func deleteCorrection(id: UUID) { corrections.removeAll { $0.id == id } }
    public mutating func invalidateCorrections(sessions: [SessionRecord]) {
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cached: [UUID: [String: Passage]] = [:]
        corrections.removeAll { correction in
            guard let session = byID[correction.sourceSessionID], session.languageID == correction.languageID else { return true }
            if cached[session.id] == nil {
                cached[session.id] = Dictionary(session.passages.filter { $0.speaker == .user }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            }
            guard let passage = cached[session.id]?[correction.sourcePassageID] else { return true }
            return passage.revisionKey != correction.revisionKey || passage.text != correction.original
        }
    }
    public func merging(_ incoming: PracticeLibrary) throws -> PracticeLibrary {
        try incoming.validate(); var out = self
        for value in incoming.expressions where !out.expressions.contains(where: { $0.id == value.id }) { _ = try out.saveExpression(value) }
        for value in incoming.corrections where !out.corrections.contains(where: { $0.id == value.id }) { out.corrections.append(value) }
        try out.validate(); return out
    }
    public func validate() throws {
        func text(_ s: String, _ max: Int, empty: Bool = false) -> Bool { (empty || !s.trimmingCharacters(in: Self.whitespace).isEmpty) && s.unicodeScalars.count <= max }
        func date(_ d: Date) -> Bool { d >= .distantPast && d <= .distantFuture }
        guard expressions.count <= 2_000, corrections.count <= 2_000, Set(expressions.map(\.id)).count == expressions.count, Set(corrections.map(\.id)).count == corrections.count else { throw ArchiveError.invalid }
        for e in expressions {
            guard LanguageRegistry.module(for: e.languageID) != nil else { throw ArchiveError.unsupportedLanguage }
            guard text(e.text, 2000), text(e.meaning, 4000), text(e.context, 4000), date(e.createdAt), e.sourcePassageID.map({ text($0, 4000) }) ?? true, e.revisionKey.map({ text($0, 4000) }) ?? true else { throw ArchiveError.invalid }
        }
        for c in corrections {
            guard LanguageRegistry.module(for: c.languageID) != nil else { throw ArchiveError.unsupportedLanguage }
            guard text(c.original, 2000), text(c.corrected, 2000), text(c.explanation, 4000), text(c.sourcePassageID, 4000), text(c.revisionKey, 4000), date(c.createdAt), c.rehearsedAt.map(date) ?? true else { throw ArchiveError.invalid }
        }
    }
}
