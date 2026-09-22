import Foundation

public struct GatewayConfig: Codable, Equatable {
    public var baseURL: String
    public var model: String

    public init(baseURL: String, model: String = "") {
        self.baseURL = baseURL
        self.model = model
    }

    /// Normalized API root: scheme added if missing, no trailing slash,
    /// `/v1` appended unless the user already supplied a version segment
    /// (…/v1, …/v2). Handles: https://api.openai.com, api.openai.com,
    /// http://localhost:1234/v1, https://openrouter.ai/api/v1,
    /// https://llm.kimchi.dev/openai -> …/openai/v1
    public var apiRoot: URL? {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let comps = URLComponents(string: s), comps.host != nil else { return nil }
        let segments = comps.path.split(separator: "/").map(String.init)
        if let last = segments.last,
           last.count > 1,
           last.hasPrefix("v"),
           last.dropFirst().allSatisfy(\.isNumber) {
            return comps.url
        }
        var withV1 = comps
        withV1.path = comps.path + "/v1"
        return withV1.url
    }
}
