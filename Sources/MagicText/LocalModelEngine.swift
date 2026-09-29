import Foundation
import Darwin
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
import MagicTextCore

/// Runs a local MLX model on-device for refinement. One loaded model at a time.
///
/// Lifecycle invariants:
///  - `context` and `loadedModelID` are committed together, only on full success.
///    A download that succeeds and an MLX init that fails must NOT leave the
///    engine in a state where it claims a model is loaded.
///  - A pre-flight memory check (see `Memory.preflight`) runs before MLX init
///    so we fail with a clear reason instead of OOM-ing the process.
///  - The most recent failure is surfaced via `lastError` for the UI.
@MainActor
final class LocalModelEngine {
    static let shared = LocalModelEngine()

    private(set) var loadedModelID: String?
    private var context: ModelContext?
    private var loading = false
    private(set) var lastError: String?

    var isLoading: Bool { loading }

    /// HF cache layout: ~/.cache/huggingface/hub/models--<owner>--<name>
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
    ///
    /// Two phases: the HF download (disk-bound, can take a while) and the MLX
    /// model materialization (memory-bound, can OOM). On the second phase we
    /// run a pre-flight check and surface a clear error if the model would not
    /// fit comfortably — better than crashing the process or the Settings UI.
    func load(id: String, progress: ((Double) -> Void)? = nil) async throws {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        // Pre-flight only matters on the first load of this process; if a model
        // is already live we know the previous allocation succeeded.
        if context == nil, let m = LocalModelCatalog.all.first(where: { $0.id == id }),
           case .tooTight(let haveGB, let needGB) = Memory.preflight(neededGB: m.ramNeededGB) {
            let msg = "Not enough free memory for \(m.name). Need \(needGB, specifier: "%.0f") GB, " +
                "your Mac has ~\(haveGB, specifier: "%.0f") GB available. " +
                "Try a smaller model or close other apps."
            lastError = msg
            throw LocalModelError.preflightFailed(msg)
        }

        do {
            // 1) Download via MLX's hub helper (progress reported during this phase).
            let newContext = try await loadModel(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                id: id,
                progressHandler: { p in
                    let fraction = p.totalUnitCount > 0 ? Double(p.completedUnitCount) / Double(p.totalUnitCount) : 0
                    progress?(fraction)
                })

            // 2) Commit BOTH pieces of state together. If any of this throws
            //    we leave the prior (or empty) state intact — a half-loaded
            //    model used to corrupt `loadedModelID` and crash on next refine.
            context = newContext
            loadedModelID = id
            lastError = nil
        } catch {
            // Preserve the old model if we had one. Don't touch `context` or
            // `loadedModelID`; they may still point at a working model.
            lastError = error.localizedDescription
            throw error
        }
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

    // MARK: - Memory pre-flight

    enum Memory {
        /// Rough free-memory estimate (GB). Uses `host_statistics64` when
        /// available; otherwise falls back to total system memory as a
        /// permissive estimate. Not exact, but good enough to catch the
        /// obvious "MLX 3B on an 8 GB active machine" cases before we OOM.
        static func availableGB() -> Double {
            // Total physical memory via mach (already used by LocalModelCatalog).
            var stats = host_basic_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let basicOK = withUnsafeMutablePointer(to: &stats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
                }
            } == KERN_SUCCESS

            // Free memory via vm_statistics64.
            var vm = vm_statistics64_data_t()
            var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
            let vmOK = withUnsafeMutablePointer(to: &vm) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
                }
            } == KERN_SUCCESS

            if vmOK {
                let page: Double = 4096
                let free = Double(vm.free_count) * page / 1_073_741_824
                let inactive = Double(vm.inactive_count) * page / 1_073_741_824
                let available = free + inactive * 0.5  // inactive pages are reclaimable
                return available
            }

            if basicOK {
                return Double(stats.max_mem) / 1_073_741_824
            }
            return 0
        }

        enum Preflight {
            case ok
            case tooTight(haveGB: Double, needGB: Double)
        }

        /// Returns `.tooTight` if the model would need > 90 % of available
        /// memory. The 90 % ceiling keeps the system responsive even if our
        /// estimate is pessimistic.
        static func preflight(neededGB: Double) -> Preflight {
            let have = availableGB()
            guard have > 0 else { return .ok }  // unknown -> let MLX try
            if neededGB > have * 0.9 { return .tooTight(haveGB: have, needGB: neededGB) }
            return .ok
        }
    }
}

enum LocalModelError: LocalizedError {
    case noModelLoaded
    case emptyOutput
    case preflightFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: "No local model loaded — open Model Manager"
        case .emptyOutput: "The local model returned nothing"
        case .preflightFailed(let msg): msg
        }
    }
}
