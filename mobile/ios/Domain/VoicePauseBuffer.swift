import Foundation

/// Recognition segments are not whole turns. Only a quiet interval releases pending speech.
public struct VoicePauseBuffer: Sendable {
    public static let choices = [5, 10, 20, 30]
    public let seconds: Int
    private var completed = ""
    private var partial = ""
    private var lastActivity: TimeInterval?
    public init(seconds: Int = 5) { self.seconds = Self.choices.contains(seconds) ? seconds : 5 }
    public var text: String { String([completed, partial].filter { !$0.isEmpty }.joined(separator: " ").prefix(2000)) }
    public var hasPendingInput: Bool { !text.isEmpty }

    @discardableResult public mutating func update(_ value: String, at now: TimeInterval) -> Bool {
        let value = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard now.isFinite, now >= 0, !value.isEmpty, value != partial else { return false }
        partial = value; speech(at: now)
        return true
    }
    public mutating func finishSegment() { completed = text; partial = "" }
    public mutating func discardPartial() { partial = "" }
    public mutating func speech(at now: TimeInterval) {
        guard now.isFinite, now >= 0 else { return }
        lastActivity = max(lastActivity ?? now, now)
    }
    public func remaining(at now: TimeInterval) -> TimeInterval? {
        guard hasPendingInput, let lastActivity, now.isFinite else { return nil }
        return max(0, Double(seconds) - max(0, now - lastActivity))
    }
    public mutating func reset() { completed = ""; partial = ""; lastActivity = nil }
}
