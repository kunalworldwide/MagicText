import SwiftUI
import AppKit
import Carbon.HIToolbox
import MagicTextCore

// MARK: - Backend tab

struct BackendTabView: View {
    let flow: RefineFlow

    @State private var baseURL: String
    @State private var apiKey: String = ""
    @State private var savedKey: Bool = false
    @State private var selectedModel: String
    @State private var models: [String] = []
    @State private var modelsMessage: String?
    @State private var fetching = false
    @State private var tone: Tone
    @State private var hotkey: Hotkey
    @State private var recording = false
    @State private var hotkeyError: String?

    init(flow: RefineFlow) {
        self.flow = flow
        let config = RefineFlow.Storage.loadConfig()
        _baseURL = State(initialValue: config?.baseURL ?? "")
        _selectedModel = State(initialValue: config?.model ?? "")
        _tone = State(initialValue: RefineFlow.Storage.loadTone())
        _hotkey = State(initialValue: RefineFlow.Storage.loadHotkey())
    }

    var isPreset: Bool { GatewayPresets.matching(url: baseURL) != nil || baseURL.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                providerCard
                credentialsCard
                modelCard
                toneAndShortcutCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Provider", subtitle: providerFooter)
            SettingsCard {
                Picker("Provider", selection: $baseURL) {
                    Text("Custom…").tag("")
                    ForEach(GatewayPresets.all) { p in
                        Text(p.name).tag(p.baseURL)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                if baseURL.isEmpty {
                    TextField("Base URL", text: $baseURL, prompt: Text("https://your-gateway/v1"))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
            }
        }
        .onChange(of: baseURL) { save() }
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Credentials",
                                  subtitle: "Stored in the macOS Keychain. Ollama / LM Studio / local servers need no key.")
            SettingsCard {
                HStack(spacing: 10) {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { newKey in
                            // Only ever write; an empty field must never wipe a stored key.
                            let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                SystemKeychain().save(trimmed, for: KeychainAccount.gatewayKey)
                                savedKey = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedKey = false }
                            }
                            save()
                        }
                    if savedKey {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Model",
                                  subtitle: "The gateway model used to refine text in place.")
            SettingsCard {
                HStack(spacing: 10) {
                    Button {
                        fetchModels()
                    } label: {
                        Label(fetching ? "Fetching…" : "Fetch Models",
                              systemImage: fetching ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    }
                    .disabled(fetching || baseURL.isEmpty)
                    if fetching {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                if !models.isEmpty {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedModel) { save() }
                } else if !selectedModel.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Current: \(selectedModel)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                if let msg = modelsMessage {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var toneAndShortcutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("Tone & Shortcut",
                                  subtitle: "How refinements sound and how you trigger them.")
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Tone").font(.system(size: 12, weight: .medium)).frame(width: 80, alignment: .leading)
                        Picker("", selection: $tone) {
                            ForEach(Tone.allCases) { t in
                                Text(t.label).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Spacer()
                    }
                    .onChange(of: tone) { save() }

                    Divider()

                    HStack(spacing: 12) {
                        Text("Shortcut").font(.system(size: 12, weight: .medium)).frame(width: 80, alignment: .leading)
                        Text(hotkey.displayString)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(minWidth: 100)
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                        Button(recording ? "Press keys… (Esc cancels)" : "Record") {
                            recording = true
                            HotkeyRecorder.shared.start { result in
                                recording = false
                                guard let result else { return }
                                if flow.applyHotkey(result) {
                                    hotkey = result
                                    hotkeyError = nil
                                } else {
                                    hotkeyError = "That combo is taken or reserved — try another"
                                }
                            }
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                    if let err = hotkeyError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    Text("Select text anywhere, press the shortcut, and MagicText refines it in place.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var providerFooter: String {
        if let p = GatewayPresets.matching(url: baseURL) { return p.note }
        if baseURL.isEmpty { return "Pick a provider or enter any OpenAI-compatible endpoint." }
        return "Any OpenAI-compatible endpoint"
    }

    private func save() {
        flow.saveBackend(baseURL: baseURL, model: selectedModel, tone: tone, hotkey: hotkey)
    }

    private func fetchModels() {
        fetching = true
        modelsMessage = nil
        let config = GatewayConfig(baseURL: baseURL, model: "")
        let client = GatewayClient(config: config, keychain: SystemKeychain(),
                                   session: GatewayClient.defaultSession)
        Task { @MainActor in
            defer { fetching = false }
            do {
                models = try await client.listModels()
                if !models.contains(selectedModel) {
                    selectedModel = models.first ?? ""
                }
                save()
            } catch let e as GatewayError {
                modelsMessage = Self.errorText(e)
            } catch {
                modelsMessage = "Network error — check the URL"
            }
        }
    }

    static func errorText(_ e: GatewayError) -> String {
        switch e {
        case .badURL: "That URL doesn't look right"
        case .unauthorized: "401/403 — the API key was rejected"
        case .server(let code, _): "Server error \(code)"
        case .emptyResponse: "No models returned — is this an OpenAI-compatible endpoint?"
        case .network: "Network error — check the URL"
        }
    }
}

// MARK: - Hotkey recorder (unchanged)

final class HotkeyRecorder {
    static let shared = HotkeyRecorder()
    private var monitor: Any?

    private func removeMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    func start(completion: @escaping (Hotkey?) -> Void) {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event -> NSEvent? in
            // Bare modifier presses (⌘, ⌥, ⇧, ⌃) are not shortcuts — keep
            // listening for the real key instead of recording garbage.
            if Self.modifierKeyCodes.contains(event.keyCode) {
                return event
            }
            self?.removeMonitor()
            if event.keyCode == UInt16(kVK_Escape) {
                completion(nil)
                return nil
            }
            let modifiers = Hotkey.carbonMask(from: event.modifierFlags)
            guard modifiers != 0 else {
                NSSound.beep()
                completion(nil)
                return nil
            }
            completion(Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            return nil
        }
    }

    /// Virtual key codes of the modifier keys themselves (left + right).
    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_CapsLock), UInt16(kVK_Option),
        UInt16(kVK_Control), UInt16(kVK_RightCommand), UInt16(kVK_RightShift),
        UInt16(kVK_RightOption), UInt16(kVK_RightControl), UInt16(kVK_Function),
    ]

    func cancel() {
        removeMonitor()
    }
}
