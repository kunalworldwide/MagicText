import Foundation
import AppKit
import Carbon.HIToolbox

public struct Hotkey: Codable, Equatable {
    /// Carbon virtual key code.
    public var keyCode: UInt32
    /// Carbon modifier mask (cmdKey | optionKey | controlKey | shiftKey).
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A usable global shortcut needs at least one modifier.
    public var isValid: Bool { modifiers != 0 }

    public static let `default` = Hotkey(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    public var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (Self.keySymbols[keyCode] ?? "Key \(keyCode)")
    }

    /// NSEvent modifier flags -> Carbon mask (for the recorder UI).
    public static func carbonMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    static let keySymbols: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_F): "F", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_ANSI_X): "X", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9", UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_Equal): "=", UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]", UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`", UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_Escape): "Esc", UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→", UInt32(kVK_DownArrow): "↓", UInt32(kVK_UpArrow): "↑",
    ]
}
