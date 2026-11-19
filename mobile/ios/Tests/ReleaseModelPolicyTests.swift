import Foundation
import XCTest
import TideEnglishCore

final class ReleaseModelPolicyTests: XCTestCase {
    private var fixture: [String: Any] {
        get throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../../packages/fixtures/cross-platform/release-model-policy.json")
            return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
    }

    func testSharedModelsAndActualRequestBoundary() throws {
        let fixture = try fixture
        var metadata = try XCTUnwrap(fixture["metadata"] as? [String: Any])
        func policy() throws -> ReleaseModelPolicy {
            ReleaseModelPolicy(source: try JSONSerialization.data(withJSONObject: metadata), debug: false)
        }
        let declared = try policy()
        var chat = ProviderConfiguration(provider: .openAI)
        chat.model = "synthetic-chat"
        let request = try declared.request("responses", body: ["model": chat.model], configuration: chat) { "synthetic-key" }
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(declared.chatChoices.count, 4)
        XCTAssertTrue(declared.permitsNative(chat))
        let liveBody = ["session": ["model": "gpt-live-1"]]
        XCTAssertNoThrow(try declared.request("live/sessions", body: liveBody, configuration: chat) { "synthetic-key" })
        func blocked(_ policy: ReleaseModelPolicy, _ path: String, _ body: [String: Any], _ config: ProviderConfiguration,
                     file: StaticString = #filePath, line: UInt = #line) {
            var reads = 0
            XCTAssertThrowsError(try policy.request(path, body: body, configuration: config) { reads += 1; return "synthetic-key" }, file: file, line: line)
            XCTAssertEqual(reads, 0, file: file, line: line)
        }
        blocked(declared, "responses", ["model": "synthetic-override"], chat)
        blocked(declared, "live/sessions", ["model": "gpt-live-1"], chat)
        blocked(declared, "live/sessions", ["session": ["model": chat.model]], chat)
        blocked(declared, "responses", ["model": chat.model], ProviderConfiguration(provider: .deepSeek))
        var custom = try XCTUnwrap(declared.chatChoices.first { $0.provider == .custom })
        let customRequest = try declared.request("chat/completions", body: ["model": custom.model], configuration: custom) { "synthetic-key" }
        XCTAssertEqual(customRequest.url?.absoluteString, "https://xn--bcher-kva.synthetic-model.org/v1/chat/completions")
        custom.baseURL += "/other"
        blocked(declared, "chat/completions", ["model": custom.model], custom)
        let glm = try XCTUnwrap(declared.chatChoices.first { $0.provider == .glm })
        let gemini = try XCTUnwrap(declared.chatChoices.first { $0.provider == .gemini })
        XCTAssertFalse(declared.permitsNative(glm))
        XCTAssertTrue(declared.permitsNative(gemini))
        let services = try XCTUnwrap(metadata["aiServices"] as? [[String: String]])
        metadata["aiServices"] = services.filter { !["models/gemini-3.8-live", "gpt-live-1"].contains($0["model"] ?? "") }
        XCTAssertFalse(try policy().permitsNative(gemini))
        blocked(try policy(), "live/sessions", liveBody, chat)
        for bad in try XCTUnwrap(fixture["invalidDeclarations"] as? [[String: String]]) {
            metadata["aiServices"] = services + [bad]
            blocked(try policy(), "responses", ["model": chat.model], chat)
        }
        metadata["aiServices"] = []
        blocked(try policy(), "responses", ["model": chat.model], chat)
        metadata["modelPolicy"] = "unrestricted"
        XCTAssertNoThrow(try policy().requireChat(custom))
        XCTAssertTrue(try policy().permitsNative(glm))
        blocked(ReleaseModelPolicy(source: nil, debug: false), "responses", ["model": chat.model], chat)
        blocked(ReleaseModelPolicy(source: Data("{}".utf8), debug: false), "responses", ["model": chat.model], chat)
        XCTAssertFalse(ReleaseModelPolicy(source: nil, debug: true).restricted)
    }

    func testSharedPublicURLs() throws {
        let fixture = try fixture
        for url in try XCTUnwrap(fixture["validURLs"] as? [String]) {
            XCTAssertEqual(publicHTTPSURL(url)?.absoluteString, url)
        }
        for url in try XCTUnwrap(fixture["invalidURLs"] as? [String]) { XCTAssertNil(publicHTTPSURL(url), url) }
    }
}
