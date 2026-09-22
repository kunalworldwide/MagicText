import AppKit
import ApplicationServices
import MagicTextCore

// MagicText — menu bar app entry point.
// LSUIElement=true in Info.plist keeps it out of the Dock.

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem!
    private var flow: RefineFlow!
    private let hotkeyCenter = HotkeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        flow = RefineFlow(hotkeyCenter: hotkeyCenter)
        hotkeyCenter.onTrigger = { [weak self] in self?.flow.run() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wand.and.stars",
                                           accessibilityDescription: "MagicText")
        rebuildMenu()

        if !AXIsProcessTrusted() {
            flow.requestAccessibility()
        }

        // Register saved (or default) hotkey.
        let hk = RefineFlow.Storage.loadHotkey()
        hotkeyCenter.register(hk)

        // First run: no gateway yet -> open Settings.
        if RefineFlow.Storage.loadConfig()?.baseURL.isEmpty != false {
            DispatchQueue.main.async { [weak self] in
                self?.flow.openSettings()
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let trusted = AXIsProcessTrusted()
        if !trusted {
            let warn = NSMenuItem(title: "⚠ Grant Accessibility…", action: #selector(grantAccess),
                                  keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let copy = NSMenuItem(title: "Copy Original", action: #selector(copyOriginal),
                              keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MagicText", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func openSettings() { MainActor.assumeIsolated { flow.openSettings() } }
    @objc private func copyOriginal() { MainActor.assumeIsolated { flow.copyOriginal() } }
    @objc private func grantAccess() {
        MainActor.assumeIsolated { flow.requestAccessibility() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.rebuildMenu()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
