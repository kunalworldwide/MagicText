import SwiftUI
import AppKit
import ApplicationServices
import MagicTextCore

/// Orchestrates: hotkey -> read selection -> refine (gateway or local) -> replace.
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
        /// "" = cloud gateway; a model id = local MLX model.
        static func localBackendID() -> String {
            defaults.string(forKey: "backend") ?? ""
        }
        static func saveLocalBackendID(_ id: String) {
            defaults.set(id, forKey: "backend")
        }
    }

    private(set) var phase: Phase?
    private(set) var lastOriginal: String?
    private var lastCapture: TextEngine.Capture?
    /// Re-entrancy guard: a second hotkey press while one refinement is in
    /// flight must never paste a second time.
    private var inFlight = false

    let overlay = OverlayWindow()
    private let hotkeyCenter: HotkeyCenter
    private var settingsWindowController: NSWindowController?

    init(hotkeyCenter: HotkeyCenter) {
        self.hotkeyCenter = hotkeyCenter
    }

    func run() {
        guard !inFlight else { return }
        guard AXIsProcessTrusted() else {
            show(.failed("Needs Accessibility permission — click the menu bar icon"))
            scheduleHide(after: 4)
            return
        }
        let usingLocal = !Storage.localBackendID().isEmpty
        if !usingLocal {
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
        } else if !LocalModelEngine.shared.isReady {
            // Cold start after a relaunch: kick off the load now so the next
            // press works instead of failing forever.
            let id = Storage.localBackendID()
            if !LocalModelEngine.shared.isLoading, LocalModelEngine.shared.isDownloaded(id) {
                Task { try? await LocalModelEngine.shared.load(id: id) }
            }
            show(.failed("Local model loading — try again in a moment"))
            scheduleHide(after: 3)
            return
        }

        inFlight = true
        phase = .reading
        show(.reading)
        Task {
            defer { inFlight = false }
            let started = Date()
            // AX reads and pasteboard simulation block (sync RPC + short
            // waits) — run them off the main actor so the UI never stalls.
            let capture = await Task.detached(priority: .userInitiated) {
                TextEngine.readSelection()
            }.value
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
                let tone = Storage.loadTone()
                let refined: String
                let modelLabel: String
                if usingLocal {
                    let id = Storage.localBackendID()
                    refined = try await LocalModelEngine.shared.refine(capture.text, tone: tone)
                    modelLabel = id.components(separatedBy: "/").last ?? id
                } else {
                    let config = try requireConfig()
                    let client = GatewayClient(config: config, keychain: SystemKeychain(),
                                                session: GatewayClient.defaultSession)
                    refined = try await client.refine(capture.text, tone: tone)
                    modelLabel = config.model
                }
                phase = .writing
                show(.writing)
                let ok = await Task.detached(priority: .userInitiated) {
                    TextEngine.replace(capture, with: refined)
                }.value
                if ok {
                    phase = .done
                    show(.done)
                    scheduleHide(after: 1.5)
                    UsageLog.shared.record(UsageRecord(
                        app: frontmostAppName(), model: modelLabel,
                        backend: usingLocal ? "local" : "gateway",
                        inputChars: capture.text.count, outputChars: refined.count,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000)))
                } else {
                    show(.failed("Couldn't write back to this app"))
                    scheduleHide(after: 3)
                    UsageLog.shared.record(UsageRecord(
                        app: frontmostAppName(), model: modelLabel,
                        backend: usingLocal ? "local" : "gateway",
                        inputChars: capture.text.count, outputChars: 0,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000), success: false))
                }
            } catch let e as GatewayError {
                show(.failed(Self.describe(e)))
                scheduleHide(after: 4)
            } catch {
                show(.failed(error.localizedDescription))
                scheduleHide(after: 4)
            }
        }
    }

    private func requireConfig() throws -> GatewayConfig {
        guard let config = Storage.loadConfig(), !config.baseURL.isEmpty else {
            throw LocalModelError.noModelLoaded
        }
        return config
    }

    @discardableResult
    func applyHotkey(_ hk: Hotkey) -> Bool {
        // Register first, persist only on success — a saved-but-unusable
        // combo would leave the app hotkey-less after the next launch.
        guard hotkeyCenter.register(hk) else { return false }
        Storage.saveHotkey(hk)
        return true
    }

    /// Called by the Settings UI whenever anything changes.
    func saveBackend(baseURL: String, model: String, tone: Tone, hotkey: Hotkey) {
        Storage.saveConfig(GatewayConfig(baseURL: baseURL, model: model))
        Storage.saveTone(tone)
        applyHotkey(hotkey)
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
            let view = SidebarSettingsView(flow: self)
            // A titled window with a standard Edit menu gives ⌘C/⌘V/⌘X/⌘A key
            // equivalents to all text fields inside (borderless panels lack them).
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                                   styleMask: [.titled, .closable, .miniaturizable],
                                   backing: .buffered, defer: false)
            window.title = "MagicText"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.minSize = NSSize(width: 720, height: 540)
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

    private func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
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
