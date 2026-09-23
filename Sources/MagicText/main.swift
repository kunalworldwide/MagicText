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
        appMenu.addItem(withTitle: "Settings…", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "")
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
            if let appIcon = NSImage(named: "AppIcon") {
                button.image = appIcon
            } else {
                button.image = NSImage(systemSymbolName: "wand.and.stars",
                                        accessibilityDescription: "MagicText")
            }
        }
        rebuildMenu()

        if !AXIsProcessTrusted() {
            flow.requestAccessibility()
        }

        // Register saved (or default) hotkey.
        let hk = RefineFlow.Storage.loadHotkey()
        hotkeyCenter.register(hk)

        // First run: no gateway yet -> open Settings.
        if RefineFlow.Storage.loadConfig()?.baseURL.isEmpty != false
            && RefineFlow.Storage.localBackendID().isEmpty {
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
