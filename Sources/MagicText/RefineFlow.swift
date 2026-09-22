import SwiftUI
import AppKit
import ApplicationServices

/// Orchestrates: hotkey -> read selection -> refine via gateway -> replace.
/// Every failure path leaves the original text untouched and surfaces a reason.
@MainActor
@Observable
final class RefineFlow {
    enum Phase: Equatable {
        case reading
        case refining
        case writing
        case done
        case failed(String)
    }

    enum Storage {
        static let defaults = UserDefaults.standard

        static func loadConfig() -> GatewayConfig? {
            guard let data = defaults.data(forKey: "gatewayConfig") else { return nil }
            return try? JSONDecoder().decode(GatewayConfig.self, from: data)
        }
        static func saveConfig(_ c: GatewayConfig) {
            defaults.set(try? JSONEncoder().encode(c), forKey: "gatewayConfig")
        }
        static func loadTone() -> Tone {
            Tone(rawValue: defaults.string(forKey: "tone") ?? "") ?? .clean
        }
        static func saveTone(_ t: Tone) {
            defaults.set(t.rawValue, forKey: "tone")
        }
        static func loadHotkey() -> Hotkey {
            guard let data = defaults.data(forKey: "hotkey"),
                  let hk = try? JSONDecoder().decode(Hotkey.self, from: data) else {
                return .default
            }
            return hk
        }
        static func saveHotkey(_ hk: Hotkey) {
            defaults.set(try? JSONEncoder().encode(hk), forKey: "hotkey")
        }
    }

    private(set) var phase: Phase?
    private(set) var lastOriginal: String?
    private var lastCapture: TextEngine.Capture?

    let overlay = OverlayWindow()
    private let hotkeyCenter: HotkeyCenter
    private var settingsWindowController: NSWindowController?

    init(hotkeyCenter: HotkeyCenter) {
        self.hotkeyCenter = hotkeyCenter
    }

    func run() {
        guard AXIsProcessTrusted() else {
            show(.failed("Needs Accessibility permission — click the menu bar icon"))
            scheduleHide(after: 4)
            return
        }
        guard let config = Storage.loadConfig(), !config.baseURL.isEmpty else {
            show(.failed("No gateway configured — open Settings"))
            scheduleHide(after: 4)
            return
        }
        guard !config.model.isEmpty else {
            show(.failed("No model selected — open Settings"))
            scheduleHide(after: 4)
            return
        }
        phase = .reading
        show(.reading)
        Task {
            let capture = TextEngine.readSelection()
            guard let capture, !capture.text.isEmpty else {
                show(.failed("No text selected"))
                scheduleHide(after: 2.5)
                return
            }
            lastOriginal = capture.text
            lastCapture = capture
            phase = .refining
            show(.refining)
            do {
                let client = GatewayClient(config: config, keychain: SystemKeychain())
                let refined = try await client.refine(capture.text, tone: Storage.loadTone())
                phase = .writing
                show(.writing)
                if TextEngine.replace(capture, with: refined) {
                    phase = .done
                    show(.done)
                    scheduleHide(after: 1.5)
                } else {
                    show(.failed("Couldn't write back to this app"))
                    scheduleHide(after: 3)
                }
            } catch let e as GatewayError {
                show(.failed(Self.describe(e)))
                scheduleHide(after: 4)
            } catch {
                show(.failed("Network error"))
                scheduleHide(after: 4)
            }
        }
    }

    @discardableResult
    func applyHotkey(_ hk: Hotkey) -> Bool {
        Storage.saveHotkey(hk)
        return hotkeyCenter.register(hk)
    }

    func copyOriginal() {
        guard let text = lastOriginal else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(flow: self)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                                   styleMask: [.titled, .closable, .miniaturizable],
                                   backing: .buffered, defer: false)
            window.title = "MagicText Settings"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func show(_ p: Phase) {
        phase = p
        overlay.show(state: p, near: NSEvent.mouseLocation)
    }

    private func scheduleHide(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.overlay.hide()
        }
    }

    private static func describe(_ e: GatewayError) -> String {
        switch e {
        case .badURL: "The gateway URL looks wrong"
        case .unauthorized: "API key rejected (401/403)"
        case .server(let code, _): "Gateway error \(code)"
        case .emptyResponse: "Model returned nothing"
        case .network: "Network error"
        }
    }
}
