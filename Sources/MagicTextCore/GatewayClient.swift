import Foundation

public enum GatewayError: Error, Equatable {
    case badURL
    case unauthorized
    case server(Int, String)
    case emptyResponse
    case network(String)
}

public final class GatewayClient {
    private let config: GatewayConfig
    private let keychain: KeychainStore
    private let session: URLSession
    private let overrideKey: String?

    public init(config: GatewayConfig,
                keychain: KeychainStore,
                session: URLSession = .shared,
                overrideKey: String? = nil) {
        self.config = config
        self.keychain = keychain
        self.session = session
        self.overrideKey = overrideKey
    }

    private var apiKey: String? {
        if let k = overrideKey, !k.isEmpty { return k }
        if let k = keychain.read(KeychainAccount.gatewayKey), !k.isEmpty { return k }
        return nil
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let root = config.apiRoot else { throw GatewayError.badURL }
        return root.appendingPathComponent(path)
    }

    private func check(_ data: Data, status: Int) throws {
        if status == 401 || status == 403 { throw GatewayError.unauthorized }
        guard (200..<300).contains(status) else {
            throw GatewayError.server(status, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
    }

    // MARK: GET /models

    public func listModels() async throws -> [String] {
        var request = URLRequest(url: try endpoint("models"))
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let status: Int
        do {
            let (d, response) = try await session.data(for: request)
            data = d
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw GatewayError.network(error.localizedDescription)
        }
        try check(data, status: status)

        // OpenAI shape: {"data":[{"id":"gpt-4o"}]}
        struct ListResponse: Decodable {
            struct M: Decodable { let id: String }
            let data: [M]
        }
        if let parsed = try? JSONDecoder().decode(ListResponse.self, from: data), !parsed.data.isEmpty {
            return parsed.data.map(\.id).sorted()
        }
        // Bare-array shape: ["model-a","model-b"]
        if let ids = try? JSONDecoder().decode([String].self, from: data), !ids.isEmpty {
            return ids.sorted()
        }
        throw GatewayError.emptyResponse
    }

    // MARK: POST /chat/completions

    public func refine(_ text: String, tone: Tone = .clean) async throws -> String {
        struct Message: Encodable { let role: String; let content: String }
        struct ChatRequest: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let max_tokens: Int
        }
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg
            }
            let choices: [Choice]
        }

        let body = ChatRequest(
            model: config.model,
            messages: [
                Message(role: "system", content: RefinementEngine.systemPrompt(for: tone)),
                Message(role: "user", content: text),
            ],
            temperature: 0,
            max_tokens: RefinementEngine.maxTokens(for: text)
        )

        var request = URLRequest(url: try endpoint("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let status: Int
        do {
            let (d, response) = try await session.data(for: request)
            data = d
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw GatewayError.network(error.localizedDescription)
        }
        try check(data, status: status)

        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw GatewayError.emptyResponse
        }
        let cleaned = RefinementEngine.stripWrappers(content)
        guard !cleaned.isEmpty else { throw GatewayError.emptyResponse }
        return cleaned
    }
}
