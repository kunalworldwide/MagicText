import Foundation

/// One refinement event. Stored as JSON lines — no DB, no dependencies.
public struct UsageRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var app: String
    public var model: String
    public var backend: String        // "gateway" or "local"
    public var inputChars: Int
    public var outputChars: Int
    public var latencyMs: Int
    public var success: Bool

    public init(id: UUID = UUID(), date: Date = Date(), app: String, model: String,
                backend: String, inputChars: Int, outputChars: Int,
                latencyMs: Int, success: Bool = true) {
        self.id = id
        self.date = date
        self.app = app
        self.model = model
        self.backend = backend
        self.inputChars = inputChars
        self.outputChars = outputChars
        self.latencyMs = latencyMs
        self.success = success
    }
}

public final class UsageLog {
    public static let shared = UsageLog()

    private let queue = DispatchQueue(label: "magictext.usagelog")
    private let maxRecords = 200
    private let url: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/MagicText")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("usage.jsonl")
    }

    public func record(_ r: UsageRecord) {
        queue.async { [url, maxRecords] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(r) {
                if let handle = FileHandle(forWritingAtPath: url.path) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.write(Data("\n".utf8))
                    try? handle.close()
                } else {
                    try? data.write(to: url)
                    if let handle = FileHandle(forWritingAtPath: url.path) {
                        handle.seekToEndOfFile()
                        handle.write(Data("\n".utf8))
                        try? handle.close()
                    }
                }
            }
            // Trim to newest maxRecords.
            if let all = Self.readAll(from: url), all.count > maxRecords {
                let keep = Array(all.suffix(maxRecords))
                let joined = keep.compactMap { rec -> String? in
                    guard let d = try? encoder.encode(rec) else { return nil }
                    return String(data: d, encoding: .utf8)
                }.joined(separator: "\n") + "\n"
                try? Data(joined.utf8).write(to: url)
            }
        }
    }

    public func allRecords() -> [UsageRecord] {
        queue.sync { Self.readAll(from: url) ?? [] }
    }

    public func clear() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }

    private static func readAll(from url: URL) -> [UsageRecord]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(UsageRecord.self, from: data)
        }
    }

    public struct Stats {
        public var total = 0
        public var successRate = 0.0
        public var avgLatencyMs = 0
        public var charsRefined = 0

        public init() {}
    }

    public func stats() -> Stats {
        let records = allRecords()
        var s = Stats()
        s.total = records.count
        guard !records.isEmpty else { return s }
        let ok = records.filter(\.success)
        s.successRate = Double(ok.count) / Double(records.count)
        s.avgLatencyMs = ok.isEmpty ? 0 : ok.map(\.latencyMs).reduce(0, +) / ok.count
        s.charsRefined = ok.map(\.inputChars).reduce(0, +)
        return s
    }
}
