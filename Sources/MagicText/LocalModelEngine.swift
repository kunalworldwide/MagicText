import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import MagicTextCore

/// Runs a local MLX model on-device for refinement. One loaded model at a time.
@MainActor
final class LocalModelEngine {
    static let shared = LocalModelEngine()

    private(set) var loadedModelID: String?
    private var context: ModelContext?
    private var loading = false

    var isLoading: Bool { loading }

    /// HF cache layout: ~/.cache/huggingface/hub/models--mlx-community--<name>
    private static func cacheDir(for id: String) -> URL {
        let hf = id.replacingOccurrences(of: "/", with: "--")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models-\(hf)")
    }

    func isDownloaded(_ id: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: Self.cacheDir(for: id).path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Deletes a downloaded model from cache.
    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: Self.cacheDir(for: id))
        if loadedModelID == id {
            context = nil
            loadedModelID = nil
        }
    }

    /// Downloads (if needed) and loads a model from Hugging Face.
    func load(id: String, progress: ((Double) -> Void)? = nil) async throws {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        context = try await loadModel(
            from: HuggingFaceDownloader(),
            using: TokenizersLoader(),
            id: id,
            progressHandler: { p in
                // Progress fraction from Foundation Progress (totalUnitCount-based).
                let fraction = p.totalUnitCount > 0 ? Double(p.completedUnitCount) / Double(p.totalUnitCount) : 0
                progress?(fraction)
            })
        loadedModelID = id
    }

    func unload() {
        context = nil
        loadedModelID = nil
    }

    var isReady: Bool { context != nil }

    /// Refine with the loaded local model. Throws if none loaded.
    func refine(_ text: String, tone: Tone) async throws -> String {
        guard let context else { throw LocalModelError.noModelLoaded }
        let prompt = RefinementEngine.systemPrompt(for: tone) + "\n\nText to refine:\n" + text
        let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
        let params = GenerateParameters(maxTokens: RefinementEngine.maxTokens(for: text), temperature: 0)
        let stream = try generate(input: input, parameters: params, context: context)
        var out = ""
        for await event in stream {
            if case .chunk(let t) = event { out += t }
        }
        let cleaned = RefinementEngine.stripWrappers(out)
        guard !cleaned.isEmpty else { throw LocalModelError.emptyOutput }
        return cleaned
    }
}

enum LocalModelError: LocalizedError {
    case noModelLoaded
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: "No local model loaded — open Model Manager"
        case .emptyOutput: "The local model returned nothing"
        }
    }
}
