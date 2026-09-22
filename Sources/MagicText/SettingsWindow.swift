import SwiftUI
import AppKit
import Carbon.HIToolbox
import MagicTextCore

struct SettingsView: View {
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

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $baseURL)
                    .autocorrectionDisabled()
                    .onChange(of: baseURL) { save() }
            } header: {
                Text("AI Gateway")
            } footer: {
                Text("Any OpenAI-compatible endpoint — https://api.openai.com/v1 · https://openrouter.ai/api/v1 · http://localhost:11434/v1 (Ollama)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SecureField("API Key (stored in Keychain)", text: $apiKey)
                    .onChange(of: apiKey) { newKey in
                        // Only ever write; empty field must never wipe a stored key.
                        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            SystemKeychain().save(trimmed, for: KeychainAccount.gatewayKey)
                            savedKey = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                savedKey = false
                            }
                        }
                        save()
                    }
                if savedKey {
                    Text("Saved ✓").font(.caption).foregroundStyle(.green)
                }
            } footer: {
                Text("Ollama/LM Studio on localhost need no key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button(fetching ? "Fetching…" : "Fetch Models") { fetchModels() }
                        .disabled(fetching || baseURL.isEmpty)
                    if fetching { ProgressView().controlSize(.small) }
                }
                if !models.isEmpty {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(models, id: \.self) { Text($0) }
                    }
                    .onChange(of: selectedModel) { save() }
                } else if !selectedModel.isEmpty {
                    Text("Current: \(selectedModel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let msg = modelsMessage {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Model")
            }

            Section {
                Picker("Tone", selection: $tone) {
                    ForEach(Tone.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .onChange(of: tone) { save() }
            } header: {
                Text("Tone")
            }

            Section {
                HStack {
                    Text(hotkey.displayString)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 110)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary.opacity(0.4))
                        )
                    Button(recording ? "Press keys… (Esc cancels)" : "Record Shortcut") {
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
                }
                if let err = hotkeyError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Global Shortcut")
            } footer: {
                Text("Select text anywhere, press the shortcut, and MagicText refines it in place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
    }

    private func save() {
        let config = GatewayConfig(baseURL: baseURL, model: selectedModel)
        RefineFlow.Storage.saveConfig(config)
        RefineFlow.Storage.saveTone(tone)
        flow.applyHotkey(hotkey)
    }

    private func fetchModels() {
        fetching = true
        modelsMessage = nil
        let config = GatewayConfig(baseURL: baseURL, model: "")
        let client = GatewayClient(config: config, keychain: SystemKeychain())
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

/// Captures the next key combo with modifiers via a local NSEvent monitor.
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.removeMonitor()
            if event.keyCode == UInt16(kVK_Escape) {
                completion(nil)
                return nil
            }
            let modifiers = Hotkey.carbonMask(from: event.modifierFlags)
            guard modifiers != 0 else {
                NSApp.beep()
                completion(nil)
                return nil
            }
            completion(Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            return nil
        }
    }

    func cancel() {
        removeMonitor()
    }
}
