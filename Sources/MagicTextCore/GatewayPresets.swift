import Foundation

/// Pre-filled gateway endpoints. The Kimchi one matches the user's actual gateway.
public struct GatewayPreset: Identifiable, Equatable {
    public let id: String        // stable id
    public let name: String
    public let baseURL: String
    public let needsKey: Bool
    public let note: String

    public init(id: String, name: String, baseURL: String, needsKey: Bool, note: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.needsKey = needsKey
        self.note = note
    }
}

public enum GatewayPresets {
    public static let all: [GatewayPreset] = [
        GatewayPreset(id: "kimchi", name: "Kimchi", baseURL: "https://llm.kimchi.dev/openai/v1", needsKey: true, note: "Fast, cheap models"),
        GatewayPreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", needsKey: true, note: "GPT-4o family"),
        GatewayPreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", needsKey: true, note: "Hundreds of models, one key"),
        GatewayPreset(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", needsKey: true, note: "Ultra-fast inference"),
        GatewayPreset(id: "together", name: "Together", baseURL: "https://api.together.xyz/v1", needsKey: true, note: "Open models, cloud"),
        GatewayPreset(id: "ollama", name: "Ollama (local server)", baseURL: "http://localhost:11434/v1", needsKey: false, note: "Runs on your machine"),
        GatewayPreset(id: "lmstudio", name: "LM Studio (local server)", baseURL: "http://localhost:1234/v1", needsKey: false, note: "Runs on your machine"),
    ]

    /// Best-effort preset match for a user-entered URL (host contains the preset host).
    public static func matching(url: String) -> GatewayPreset? {
        let lowered = url.lowercased()
        return all.first { lowered.contains($0.baseURL.lowercased()) }
    }
}
