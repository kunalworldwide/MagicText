import XCTest
@testable import MagicTextCore

final class FakeKeychain: KeychainStore {
    var store: [String: String] = [:]
    func save(_ value: String, for account: String) { store[account] = value }
    func read(_ account: String) -> String? { store[account] }
    func delete(_ account: String) { store[account] = nil }
}

final class KeychainStoreTests: XCTestCase {
    func testFakeSaveReadDelete() {
        let k = FakeKeychain()
        XCTAssertNil(k.read("a"))
        k.save("secret", for: "a")
        XCTAssertEqual(k.read("a"), "secret")
        k.delete("a")
        XCTAssertNil(k.read("a"))
    }

    func testSaveOverwrites() {
        let k = FakeKeychain()
        k.save("one", for: "a")
        k.save("two", for: "a")
        XCTAssertEqual(k.read("a"), "two")
    }
}
