import Foundation

public enum Tone: String, Codable, CaseIterable, Identifiable {
    case clean
    case formal
    case casual
    case emoji

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .clean: return "Clean — fix spelling, punctuation, grammar"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .emoji: return "Emoji"
        }
    }
}

public enum RefinementEngine {

    public static func systemPrompt(for tone: Tone) -> String {
        let contract = """
        You are a text refinement engine. Output ONLY the refined text — no quotes, \
        no preamble, no markdown fences, no commentary. Preserve the author's meaning, \
        language and formatting (line breaks) exactly.
        """
        switch tone {
        case .clean:
            return contract + " Fix spelling, grammar, punctuation and capitalization. Keep the author's wording and voice — change nothing else."
        case .formal:
            return contract + " Fix all errors and rewrite in a professional, formal tone."
        case .casual:
            return contract + " Fix all errors and rewrite in a relaxed, conversational tone."
        case .emoji:
            return contract + " Fix all errors and add tasteful, fitting emojis where they naturally belong. Do not overdo it."
        }
    }

    /// Rough token budget: ~3 chars/token, plus headroom for corrections.
    public static func maxTokens(for input: String) -> Int {
        let chars = input.utf16.count
        return min(4096, max(256, chars / 3 + 512))
    }

    /// Models sometimes wrap output in code fences or quotes despite the prompt. Strip one layer.
    public static func stripWrappers(_ output: String) -> String {
        var t = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let firstNewline = t.firstIndex(of: "\n") {
                t.removeSubrange(t.startIndex...firstNewline)
            }
            if t.hasSuffix("```") { t.removeLast(3) }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let quotePairs: [(String, String)] = [
            ("\"", "\""), ("\u{201C}", "\u{201D}"), ("'", "'"), ("\u{2018}", "\u{2019}"),
        ]
        for (open, close) in quotePairs where t.count >= 2 {
            if t.hasPrefix(open), t.hasSuffix(close) {
                t.removeFirst()
                t.removeLast()
            }
        }
        return t
    }
}
