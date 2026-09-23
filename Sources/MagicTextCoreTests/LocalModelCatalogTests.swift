import XCTest
@testable import MagicTextCore

final class LocalModelCatalogTests: XCTestCase {
    func testAllModelsHaveValidFields() {
        for m in LocalModelCatalog.all {
            XCTAssertFalse(m.id.isEmpty)
            XCTAssertTrue(m.id.hasPrefix("mlx-community/"), "\(m.id) should be an mlx-community repo")
            XCTAssertGreaterThan(m.sizeGB, 0)
            XCTAssertTrue((1...5).contains(m.quality))
            XCTAssertGreaterThan(m.ramNeededGB, m.sizeGB, "\(m.name): RAM needed must exceed download size")
        }
    }

    func testRecommendationsFitRAM() {
        // 8 GB machine -> 3.6 GB usable -> only the 1.5B (2.5) fits
        let recs8 = LocalModelCatalog.recommendations(ramGB: 8)
        XCTAssertEqual(recs8.map(\.params), ["1.5B"])

        // 16 GB machine -> 7.2 GB usable -> all 3 models fit, best quality first
        let recs16 = LocalModelCatalog.recommendations(ramGB: 16)
        XCTAssertEqual(recs16.count, 3)
        XCTAssertEqual(recs16.first?.quality, 4)

        // Tiny machine -> nothing fits
        XCTAssertTrue(LocalModelCatalog.recommendations(ramGB: 4).isEmpty)
    }

    func testPresets() {
        XCTAssertGreaterThanOrEqual(GatewayPresets.all.count, 6)
        let kimchi = GatewayPresets.matching(url: "https://llm.kimchi.dev/openai/v1")
        XCTAssertEqual(kimchi?.id, "kimchi")
        // User-typed variants still match
        XCTAssertNotNil(GatewayPresets.matching(url: "https://api.openai.com/v1/"))
        XCTAssertNil(GatewayPresets.matching(url: "https://example.com/v1"))
    }

    func testUsageLogRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("magictext-tests-\(UUID().uuidString)")
        let log = UsageLog(directory: dir)
        log.record(UsageRecord(app: "Notes", model: "gpt-4o-mini", backend: "gateway",
                               inputChars: 100, outputChars: 120, latencyMs: 800))
        log.record(UsageRecord(app: "Chrome", model: "qwen-local", backend: "local",
                               inputChars: 50, outputChars: 60, latencyMs: 300, success: false))
        // async write + sync read back
        let exp = expectation(description: "write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let records = log.allRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.app, "Notes")
        let stats = log.stats()
        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.successRate, 0.5)
        XCTAssertEqual(stats.avgLatencyMs, 800)
        log.clear()
        XCTAssertTrue(log.allRecords().isEmpty)
    }
}
