import Foundation

/// Offline validation shared with the release gate, independent of DNS or website status.
public func publicHTTPSURL(_ value: String) -> URL? {
    let pattern = #"\Ahttps://([A-Za-z0-9.-]+)(?::([0-9]{1,5}))?((?:/[A-Za-z0-9._~!$&'()*+,;=:@/%-]*)?(?:\?[A-Za-z0-9._~!$&'()*+,;=:@/?%-]*)?)\z"#
    guard value.utf8.count <= 2048, value.range(of: pattern, options: .regularExpression) != nil,
          value.range(of: #"%(?![0-9A-Fa-f]{2})|%(?:0[0-9A-Fa-f]|1[0-9A-Fa-f]|7[Ff]|5[Cc])"#, options: .regularExpression) == nil,
          let parts = URLComponents(string: value), let host = parts.host?.lowercased(), host.count <= 253,
          parts.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
    let labels = host.components(separatedBy: ".")
    let reserved = ["example.com", "example.net", "example.org", "example", "test", "invalid", "localhost", "local", "internal", "home.arpa", "onion", "alt", "localdomain", "home", "corp", "lan"]
    guard labels.count > 1, labels.allSatisfy({
        $0.range(of: #"\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z"#, options: .regularExpression) != nil
    }), let last = labels.last, last.first?.isLetter == true,
          !reserved.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
    return parts.url
}

public struct PublicMetadata: Decodable, Sendable {
    public let schemaVersion: Int
    public let publisherName, supportEmail, appFilingNumber: String
    public let publicPagesReady: Bool
    public let links: [String: String]
    fileprivate let modelPolicy: String
    fileprivate let aiServices: [Declaration]

    fileprivate struct Declaration: Decodable, Sendable {
        let provider: ModelProvider
        let model, baseURL, filingNumber: String
    }
}

public struct ReleaseModelPolicy: Sendable {
    private let declarations: [ProviderConfiguration]?
    public var restricted: Bool { declarations != nil }
    public static let openAILiveModel = "gpt-live-1"
    public var chatChoices: [ProviderConfiguration] {
        (declarations ?? []).filter {
            !($0.provider == .openAI && $0.model == Self.openAILiveModel) &&
            !($0.provider == .gemini && $0.model == GeminiLiveProtocol.model)
        }
    }

    public init(source: Data?, debug: Bool) {
        guard let source else { declarations = debug ? nil : []; return }
        guard let value = try? JSONDecoder().decode(PublicMetadata.self, from: source),
              value.schemaVersion == 1 else { declarations = []; return }
        if value.modelPolicy == "unrestricted" { declarations = nil; return }
        guard value.modelPolicy == "declaredOnly", value.aiServices.count <= 20 else { declarations = []; return }
        var choices: [ProviderConfiguration] = []
        for entry in value.aiServices {
            var config = ProviderConfiguration(provider: entry.provider)
            config.model = entry.model
            config.baseURL = entry.baseURL
            guard !entry.filingNumber.isEmpty, entry.filingNumber.unicodeScalars.count <= 500,
                  entry.filingNumber == entry.filingNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                  entry.filingNumber.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil,
                  publicHTTPSURL(config.baseURL) != nil else { declarations = []; return }
            if config.provider == .gemini && config.model == GeminiLiveProtocol.model {
                guard config.baseURL == GeminiLiveProtocol.baseURL else { declarations = []; return }
            } else if (try? config.validated()) != config { declarations = []; return }
            if !choices.contains(config) { choices.append(config) }
        }
        declarations = choices
    }

    public func requireChat(_ configuration: ProviderConfiguration) throws -> ProviderConfiguration {
        let config = try configuration.validated()
        guard !restricted || chatChoices.contains(config) else { throw Unavailable() }
        return config
    }

    private func permits(_ provider: ModelProvider, model: String?, baseURL: String) -> Bool {
        declarations?.contains { $0.provider == provider && $0.model == model && $0.baseURL == baseURL } ?? true
    }

    public func permitsNative(_ config: ProviderConfiguration) -> Bool {
        guard restricted else { return true }
        guard (try? requireChat(config)) != nil else { return false }
        switch config.provider {
        case .gemini: return permits(.gemini, model: GeminiLiveProtocol.model, baseURL: GeminiLiveProtocol.baseURL)
        case .openAI: return permits(.openAI, model: Self.openAILiveModel, baseURL: config.provider.defaultBaseURL)
        default: return false // GLM native realtime selects a server-side model.
        }
    }

    /// Returns an authenticated request only after checking the actual request shape and destination.
    public func request(_ path: String, body: [String: Any], configuration: ProviderConfiguration,
                        stream: Bool = false, credential: () throws -> String) throws -> URLRequest {
        try authorizeRequest(path, body: body, configuration: configuration)
        let key = try credential()
        var request = URLRequest(url: try configuration.endpoint(path))
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func authorizeRequest(_ path: String, body: [String: Any], configuration: ProviderConfiguration) throws {
        guard restricted else { return }
        let selected = try requireChat(configuration)
        if path == "live/sessions" {
            let actual = (body["session"] as? [String: Any])?["model"] as? String
            guard selected.provider == .openAI, actual == Self.openAILiveModel, permitsNative(selected) else { throw Unavailable() }
        } else {
            let expected = selected.provider == .openAI ? "responses" : "chat/completions"
            guard path == expected, body["model"] as? String == selected.model else { throw Unavailable() }
        }
    }

    public struct Unavailable: LocalizedError {
        public init() {}
        public var errorDescription: String? { "Choose a model available in this release in Settings." }
    }
}
