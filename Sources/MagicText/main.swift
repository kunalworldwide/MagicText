import AppKit
import ApplicationServices
import MagicTextCore

// MagicText — menu bar app entry point.
// LSUIElement=true in Info.plist keeps it out of the Dock, but we still install
// a main menu with a standard Edit menu — without it, ⌘C/⌘V/⌘X/⌘A key
// equivalents don't reach text fields (the paste bug in v0.0.1).

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem!
    private var flow: RefineFlow!
    private let hotkeyCenter = HotkeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        flow = RefineFlow(hotkeyCenter: hotkeyCenter)
        hotkeyCenter.onTrigger = { [weak self] in self?.flow.run() }

        // Standard main menu — gives every text field ⌘C/⌘V/⌘X/⌘A/⌘Z.
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let appMenu = NSMenu()
        let appSettings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appSettings.target = self
        appMenu.addItem(appSettings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MagicText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarImage()
        }
        rebuildMenu()

        if !AXIsProcessTrusted() {
            flow.requestAccessibility()
        }

        // Register saved (or default) hotkey.
        let hk = RefineFlow.Storage.loadHotkey()
        hotkeyCenter.register(hk)

        // Warm up the chosen local model in the background so the first
        // refinement after a relaunch doesn't wait on a cold load.
        let backendID = RefineFlow.Storage.localBackendID()
        if !backendID.isEmpty, LocalModelEngine.shared.isDownloaded(backendID) {
            Task { try? await LocalModelEngine.shared.load(id: backendID) }
        }

        // First run: no gateway yet -> open Settings.
        if RefineFlow.Storage.loadConfig()?.baseURL.isEmpty != false
            && RefineFlow.Storage.localBackendID().isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.flow.openSettings()
            }
        }
    }

    /// Menu bar icon: the white template glyph (assets/menubar.png). macOS
    /// recolors template images to match the menu bar in light and dark mode.
    /// Falls back to an SF Symbol if the asset is missing.
    private static func menuBarImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "wand.and.stars",
                       accessibilityDescription: "MagicText")
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
        pollTrust(remaining: 15)
    }

    /// Keep re-checking the Accessibility grant for a while — the user may
    /// take a moment in System Settings, and the warning item should clear
    /// itself once the permission lands.
    private func pollTrust(remaining: Int) {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.rebuildMenu()
            if !AXIsProcessTrusted() { self.pollTrust(remaining: remaining - 1) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
