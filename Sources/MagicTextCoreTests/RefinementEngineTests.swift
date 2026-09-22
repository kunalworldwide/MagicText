import XCTest
@testable import MagicTextCore

final class RefinementEngineTests: XCTestCase {
    func testEveryToneHasContract() {
        for tone in Tone.allCases {
            let p = RefinementEngine.systemPrompt(for: tone)
            XCTAssertTrue(p.contains("ONLY the refined text"), "\(tone) missing contract")
            XCTAssertGreaterThan(p.count, 60, "\(tone) prompt suspiciously short")
        }
    }

    func testMaxTokensFloorAndCeiling() {
        XCTAssertEqual(RefinementEngine.maxTokens(for: ""), 512)     // max(256, 0+512)
        XCTAssertEqual(RefinementEngine.maxTokens(for: "hi"), 512)  // max(256, 0+512)
        let huge = String(repeating: "a", count: 60_000)
        XCTAssertEqual(RefinementEngine.maxTokens(for: huge), 4096) // ceiling
        let mid = String(repeating: "b", count: 3000)
        XCTAssertEqual(RefinementEngine.maxTokens(for: mid), 1512)  // 1000+512
    }

    func testStripCodeFence() {
        XCTAssertEqual(RefinementEngine.stripWrappers("```\nfixed text\n```"), "fixed text")
    }

    func testStripSurroundingQuotes() {
        XCTAssertEqual(RefinementEngine.stripWrappers("\"fixed text\""), "fixed text")
        XCTAssertEqual(RefinementEngine.stripWrappers("\u{201C}fixed\u{201D}"), "fixed")
    }

    func testPlainTextUntouched() {
        XCTAssertEqual(RefinementEngine.stripWrappers("already fine."), "already fine.")
    }
}
