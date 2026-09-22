import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Reads the selected text from the frontmost app via the Accessibility API,
/// falls back to simulating Cmd+C when AX fails (web views, some apps),
/// and writes refined text back the same way.
enum TextEngine {

    struct Capture {
        let text: String
        /// The element the text came from — used to replace in place.
        let element: AXUIElement?
        let viaPasteboard: Bool
    }

    // MARK: - Read

    static func readSelection() -> Capture? {
        if let (text, element) = readViaAX() {
            return Capture(text: text, element: element, viaPasteboard: false)
        }
        if let text = readViaClipboard() {
            return Capture(text: text, element: nil, viaPasteboard: true)
        }
        return nil
    }

    private static func readViaAX() -> (String, AXUIElement)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElement as CFString,
                                            &focused) == .success,
              let element = focused as? AXUIElement else { return nil }

        if let text = selectedText(of: element), !text.isEmpty {
            return (text, element)
        }
        // Web areas sometimes nest the text field one level down.
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildren as CFString, &children) == .success,
           let kids = children as? [AXUIElement] {
            for kid in kids {
                if let text = selectedText(of: kid), !text.isEmpty {
                    return (text, kid)
                }
            }
        }
        return nil
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }

    private static func readViaClipboard() -> String? {
        let board = NSPasteboard.general
        let saved = Snapshot.of(board)
        let savedCount = board.changeCount

        postKey(UInt16(kVK_ANSI_C), modifiers: .maskCommand)
        guard wait(changeCountOf: board, exceeds: savedCount, timeout: 0.3) else {
            Snapshot.restore(saved, to: board)
            return nil
        }
        let text = board.string(forType: .string)
        Snapshot.restore(saved, to: board)
        return (text?.isEmpty == false) ? text : nil
    }

    // MARK: - Replace

    static func replace(_ capture: Capture, with newText: String) -> Bool {
        if !capture.viaPasteboard, let element = capture.element {
            if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            newText as CFString) == .success {
                return true
            }
        }
        return paste(text: newText)
    }

    private static func paste(text: String) -> Bool {
        let board = NSPasteboard.general
        let saved = Snapshot.of(board
)
        board.clearContents()
        board.setString(text, forType: .string)
        postKey(UInt16(kVK_ANSI_V), modifiers: .maskCommand)
        Thread.sleep(forTimeInterval: 0.15)
        Snapshot.restore(saved, to: board)
        return true
    }

    // MARK: - CGEvent helpers

    private static func postKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = modifiers
        up.flags = modifiers
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func wait(changeCountOf board: NSPasteboard, exceeds initial: Int,
                            timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if board.changeCount > initial { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    // MARK: - Pasteboard snapshot

    private struct Snapshot {
        let items: [[String: Data]]
        let changeCount: Int

        static func of(_ board: NSPasteboard) -> Snapshot {
            let items = (board.pasteboardItems ?? []).map { item in
                item.types.reduce(into: [String: Data]()) { acc, type in
                    if let data = item.data(forType: type) { acc[type.rawValue] = data }
                }
            }
            return Snapshot(items: items, changeCount: board.changeCount)
        }

        static func restore(_ snap: Snapshot, to board: NSPasteboard) {
            board.clearContents()
            let restored = snap.items.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
                return item
            }
            board.writeObjects(restored)
        }
    }
}
