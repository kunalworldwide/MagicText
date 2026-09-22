import XCTest
import AppKit
@testable import MagicTextCore

final class HotkeyTests: XCTestCase {
    func testDefaultIsCtrlOptCmdR() {
        let d = Hotkey.default
        XCTAssertEqual(d.keyCode, 15) // kVK_ANSI_R
        XCTAssertEqual(d.displayString, "⌃⌥⌘R")
        XCTAssertTrue(d.isValid)
    }

    func testBareKeyInvalid() {
        XCTAssertFalse(Hotkey(keyCode: 15, modifiers: 0).isValid)
    }

    func testModifierMapping() {
        let mask = Hotkey.carbonMask(from: [.command, .option, .control, .shift])
        XCTAssertEqual(mask, UInt32(cmdKey | optionKey | controlKey | shiftKey))

        let cmdOnly = Hotkey.carbonMask(from: [.command])
        XCTAssertEqual(cmdOnly, UInt32(cmdKey))
    }

    func testCodableRoundTrip() throws {
        let h = Hotkey(keyCode: 15, modifiers: UInt32(controlKey | cmdKey))
        let data = try JSONEncoder().encode(h)
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), h)
    }

    func testDisplayStringShowsShift() {
        let h = Hotkey(keyCode: UInt32(kVK_ANSI_Space), modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(h.displayString, "⇧⌘Space")
    }
}
