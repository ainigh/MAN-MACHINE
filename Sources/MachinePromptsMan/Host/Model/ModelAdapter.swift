import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// SPEC §9: the single model-specific component. `string → string`; everything else is shared script.
public protocol ModelAdapter: Sendable {
    /// A short name for the turn log.
    var name: String { get }
    /// Returns the raw model output. Must give up by `deadline` (real time).
    func complete(_ prompt: String, deadline: Date) async throws -> String
}

public enum ModelError: Error, Equatable, CustomStringConvertible {
    case notConfigured
    case http(Int, String)
    case malformedResponse(String)
    case refused(String?)
    case deadlinePassed

    public var description: String {
        switch self {
        case .notConfigured: return "no model configured"
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(300))"
        case .malformedResponse(let why): return "malformed response: \(why)"
        case .refused(let category): return "the model declined" + (category.map { " (\($0))" } ?? "")
        case .deadlinePassed: return "deadline passed before the request was sent"
        }
    }
}

/// "No model" is a valid, fully functional configuration (SPEC §9.4). Returns nothing.
public struct NullAdapter: ModelAdapter {
    public init() {}
    public var name: String { "none" }
    public func complete(_ prompt: String, deadline: Date) async throws -> String { "" }
}

/// What the settings say about the model (tasks/07). Persisted in host-settings.json; the key is not.
public struct ModelSettings: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case none, ollama, anthropic }
    public var kind: Kind = .none
    public var ollamaModel: String = "llama3.2"
    public var ollamaEndpoint: String = "http://127.0.0.1:11434"
    /// Claude Opus 5.5 by default.
    public var anthropicModel: String = "claude-opus-5-5"
    /// Round boundaries are short; `low` keeps answers inside the status phase. [default]
    public var anthropicEffort: String = "low"
    public var contextNote: String = ""
    public init() {}
}

enum HTTP {
    static func post(_ url: URL, headers: [String: String], body: Data, deadline: Date) async throws -> (Data, Int) {
        let timeout = deadline.timeIntervalSinceNow
        guard timeout > 0 else { throw ModelError.deadlinePassed }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Ollama on this machine: `/api/generate`, streaming off (tasks/07).
public struct OllamaAdapter: ModelAdapter {
    public let endpoint: URL
    public let model: String
    public init(endpoint: URL, model: String) { self.endpoint = endpoint; self.model = model }
    public var name: String { "ollama:\(model)" }

    public func complete(_ prompt: String, deadline: Date) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt, "stream": false])
        let (data, status) = try await HTTP.post(endpoint.appendingPathComponent("api/generate"),
                                                 headers: ["Content-Type": "application/json"], body: body, deadline: deadline)
        guard status == 200 else { throw ModelError.http(status, String(decoding: data, as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = obj["response"] as? String else {
            throw ModelError.malformedResponse("no response field")
        }
        return text
    }
}

/// The Anthropic Messages API over plain HTTP (Swift has no official SDK). One user message, text out.
public struct AnthropicAdapter: ModelAdapter {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public let apiKey: String
    public let model: String
    public let effort: String
    public init(apiKey: String, model: String = "claude-opus-5-5", effort: String = "low") {
        self.apiKey = apiKey; self.model = model; self.effort = effort
    }
    public var name: String { "anthropic:\(model)" }

    static func requestBody(prompt: String, model: String, effort: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16000,
            "output_config": ["effort": effort],
            // Server-side fallback on a policy decline, routed by refusal category.
            "fallbacks": "default",
            "messages": [["role": "user", "content": prompt]],
        ]
    }

    public func complete(_ prompt: String, deadline: Date) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: Self.requestBody(prompt: prompt, model: model, effort: effort))
        let (data, status) = try await HTTP.post(Self.endpoint, headers: [
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "server-side-fallback-2026-07-01",
        ], body: body, deadline: deadline)
        guard status == 200 else { throw ModelError.http(status, String(decoding: data, as: UTF8.self)) }
        return try Self.text(from: data)
    }

    /// The text blocks of a Messages API response, joined. A refusal is an error, not text.
    static func text(from data: Data) throws -> String {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelError.malformedResponse("not an object")
        }
        if obj["stop_reason"] as? String == "refusal" {
            throw ModelError.refused((obj["stop_details"] as? [String: Any])?["category"] as? String)
        }
        guard let content = obj["content"] as? [[String: Any]] else { throw ModelError.malformedResponse("no content") }
        return content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}
