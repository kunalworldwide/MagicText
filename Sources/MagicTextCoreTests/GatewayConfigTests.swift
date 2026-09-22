import XCTest
@testable import MagicTextCore

final class GatewayConfigTests: XCTestCase {
    func testBareHostGetsHTTPSAndV1() {
        let c = GatewayConfig(baseURL: "api.openai.com")
        XCTAssertEqual(c.apiRoot?.absoluteString, "https://api.openai.com/v1")
    }

    func testFullURLPreserved() {
        let c = GatewayConfig(baseURL: "https://api.openai.com/v1")
        XCTAssertEqual(c.apiRoot?.absoluteString, "https://api.openai.com/v1")
    }

    func testTrailingSlashAndSpaces() {
        let c = GatewayConfig(baseURL: "  https://api.openai.com/v1/  ")
        XCTAssertEqual(c.apiRoot?.absoluteString, "https://api.openai.com/v1")
    }

    func testLocalhostNoScheme() {
        let c = GatewayConfig(baseURL: "localhost:11434")
        XCTAssertEqual(c.apiRoot?.absoluteString, "https://localhost:11434/v1")
    }

    func testLocalhostHTTPExplicit() {
        let c = GatewayConfig(baseURL: "http://localhost:11434/v1")
        XCTAssertEqual(c.apiRoot?.absoluteString, "http://localhost:11434/v1")
    }

    func testOpenRouterKeepsV1OnlyOnce() {
        let c = GatewayConfig(baseURL: "https://openrouter.ai/api/v1/")
        XCTAssertEqual(c.apiRoot?.absoluteString, "https://openrouter.ai/api/v1")
    }

    func testSubpathGatewayGetsV1Appended() {
        let c = GatewayConfig(baseURL: "https://llm.kimchi.dev/openai")
        XCTAssertEqual(c.apiRoot?.absoluteString, "https://llm.kimchi.dev/openai/v1")
    }

    func testGarbageIsNil() {
        XCTAssertNil(GatewayConfig(baseURL: "").apiRoot)
        XCTAssertNil(GatewayConfig(baseURL: "   ").apiRoot)
        XCTAssertNil(GatewayConfig(baseURL: "not a url at all").apiRoot)
    }

    func testCodableRoundTrip() throws {
        let c = GatewayConfig(baseURL: "https://x.dev/v1", model: "m")
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(GatewayConfig.self, from: data), c)
    }
}
