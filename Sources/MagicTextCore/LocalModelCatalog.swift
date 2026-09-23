import Foundation
import IOKit

/// A downloadable local model (MLX 4-bit from mlx-community on HF).
public struct LocalModel: Codable, Equatable, Identifiable {
    public let id: String           // "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    public let name: String
    public let params: String       // "0.5B"
    public let sizeGB: Double       // download size
    public let quality: Int         // 1-5 relative refinement quality (from public benchmarks)
    public let ramNeededGB: Double  // memory to run comfortably
    public let note: String

    public init(id: String, name: String, params: String, sizeGB: Double,
                quality: Int, ramNeededGB: Double, note: String) {
        self.id = id
        self.name = name
        self.params = params
        self.sizeGB = sizeGB
        self.quality = quality
        self.ramNeededGB = ramNeededGB
        self.note = note
    }
}

public enum LocalModelCatalog {
    /// Curated shortlist of small mlx-community 4-bit instruct models that run
    /// well locally for short text refinement. Sizes are 4-bit.
    public static let all: [LocalModel] = [
        LocalModel(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen 2.5 1.5B", params: "1.5B",
                   sizeGB: 1.0, quality: 3, ramNeededGB: 2.5, note: "Fast, solid everyday fixes"),
        LocalModel(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B", params: "3B",
                   sizeGB: 2.0, quality: 4, ramNeededGB: 4.0, note: "Recommended — great English refinement"),
        LocalModel(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", name: "Qwen 2.5 3B", params: "3B",
                   sizeGB: 2.0, quality: 4, ramNeededGB: 4.0, note: "Strong multilingual refinement"),
    ]

    /// Apple Silicon unified memory, GB. 0 if unknown.
    public static func totalSystemMemoryGB() -> Int {
        var stats = host_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(stats.max_mem / 1_073_741_824) : 0
    }

    /// True on Apple Silicon — MLX only runs on Metal.
    public static func supportsLocalModels() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Models that fit this machine, best-first.
    public static func recommendations(ramGB: Int) -> [LocalModel] {
        let usable = Double(ramGB) * 0.45   // leave headroom for the OS + foreground app
        let fits = all.filter { $0.ramNeededGB <= usable }
        if fits.isEmpty { return [] }
        // Best quality that fits, then everything below it for choice.
        return fits.sorted { $0.quality > $1.quality }
    }
}
