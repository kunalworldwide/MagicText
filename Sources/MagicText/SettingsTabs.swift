import SwiftUI
import AppKit
import MagicTextCore

/// Download manager for local MLX models, with per-machine recommendation.
struct LocalModelsTabView: View {
    let flow: RefineFlow

    @State private var ramGB: Int = 0
    @State private var downloading: [String: Double] = [:]   // model id -> progress 0...1
    @State private var activeBackend: String = ""
    @State private var loadError: String?

    private let engine = LocalModelEngine.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundStyle(.secondary)
                    Text(ramGB > 0
                         ? "This Mac has \(ramGB) GB unified memory"
                         : "Memory detection unavailable")
                        .font(.callout)
                    Spacer()
                    if let rec = topRecommendation {
                        Label("Recommended for this Mac", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("Fits comfortably in your free memory")
                            .labelStyle(.titleAndIcon)
                    }
                }
                if !LocalModelCatalog.supportsLocalModels() {
                    Label("Local models need Apple Silicon (MLX runs on Metal).", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("System")
            }

            Section {
                ForEach(catalog) { m in
                    modelRow(m)
                }
            } header: {
                Text("Models (download from Hugging Face)")
            } footer: {
                Text("4-bit MLX builds. Downloaded to ~/.cache/huggingface — reusable by other MLX apps.")
            }

            Section {
                HStack {
                    Text(activeBackend.isEmpty ? "Using cloud gateway" : "Local model active: \(activeBackend)")
                        .font(.callout)
                        .foregroundStyle(activeBackend.isEmpty ? Color.secondary : Color.green)
                    Spacer()
                    if engine.isLoading {
                        ProgressView().controlSize(.small)
                        Text("Loading model…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let err = loadError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Active")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            ramGB = LocalModelCatalog.totalSystemMemoryGB()
            activeBackend = UserDefaults.standard.string(forKey: "backend") ?? ""
            refreshDownloadedFlags()
        }
    }

    private var catalog: [LocalModel] { LocalModelCatalog.all }

    private var topRecommendation: LocalModel? {
        LocalModelCatalog.recommendations(ramGB: ramGB).first
    }

    private func refreshDownloadedFlags() {
        // forces view refresh; isDownloaded reads the HF cache each render
    }

    private func modelRow(_ m: LocalModel) -> some View {
        let downloaded = engine.isDownloaded(m.id)
        let isTop = topRecommendation?.id == m.id
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.name).font(.system(size: 13, weight: .semibold))
                    if isTop && !downloaded {
                        Text("RECOMMENDED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(m.params) · \(m.sizeGB, specifier: "%.1f") GB · needs \(m.ramNeededGB, specifier: "%.0f") GB RAM")
                    .font(.caption).foregroundStyle(.secondary)
                Text(m.note).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            qualityStars(m.quality)
            if let progress = downloading[m.id] {
                if progress <= 0 {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 90)
                    Text("…").font(.caption).frame(width: 34, alignment: .trailing)
                } else {
                    ProgressView(value: progress)
                        .frame(width: 90)
                    Text("\(Int(progress * 100))%")
                        .font(.caption).monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            } else if downloaded {
                Button("Delete") {
                    engine.delete(m.id)
                    if activeBackend == m.id {
                        UserDefaults.standard.set("", forKey: "backend")
                        activeBackend = ""
                    }
                }
                .controlSize(.small)
                Button("Use") {
                    Task { await useModel(m.id) }
                }
                .controlSize(.small)
            } else {
                Button("Download") {
                    Task { await downloadModel(m) }
                }
                .controlSize(.small)
                .disabled(!LocalModelCatalog.supportsLocalModels())
            }
        }
        .padding(.vertical, 2)
    }

    private func qualityStars(_ q: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= q ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
        }
        .help("Relative refinement quality")
    }

    private func useModel(_ id: String) async {
        loadError = nil
        do {
            if !engine.isReady || engine.loadedModelID != id {
                try await engine.load(id: id)
            }
            UserDefaults.standard.set(id, forKey: "backend")
            activeBackend = id
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func downloadModel(_ m: LocalModel) async {
        loadError = nil
        do {
            downloading[m.id] = 0
            defer { downloading[m.id] = nil }
            // load() downloads on first use (HF hub API) — progress via delegate is
            // not exposed here, so we show an indeterminate strip until done.
            try await engine.load(id: m.id)
            UserDefaults.standard.set(m.id, forKey: "backend")
            activeBackend = m.id
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Usage & History tab

struct UsageTabView: View {
    let flow: RefineFlow
    @State private var records: [UsageRecord] = []
    @State private var stats: UsageLog.Stats = UsageLog.Stats()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 24) {
                    statBox("Refinements", "\(stats.total)")
                    statBox("Success", "\(Int(stats.successRate * 100))%")
                    statBox("Avg latency", "\(stats.avgLatencyMs) ms")
                    statBox("Characters", "\(stats.charsRefined)")
                }
            } header: {
                Text("All-time")
            }

            Section {
                if records.isEmpty {
                    Text("No refinements yet — select text anywhere and press \(RefineFlow.Storage.loadHotkey().displayString).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Table(records) {
                        TableColumn("Date") { r in
                            Text(r.date.formatted(.dateTime.month().day().hour().minute().second()))
                        }.width(min: 130)
                        TableColumn("App") { r in Text(r.app) }.width(min: 70)
                        TableColumn("Model") { r in Text(r.model) }.width(min: 110)
                        TableColumn("Chars") { r in
                            Text("\(r.inputChars) → \(r.outputChars)").monospacedDigit()
                        }.width(min: 70)
                        TableColumn("Latency") { r in
                            Text("\(r.latencyMs) ms").monospacedDigit()
                        }.width(min: 60)
                        TableColumn("Status") { r in
                            if r.success {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                        }.width(min: 40)
                    }
                }
            } header: {
                Text("History (last 200)")
            }

            Section {
                Button("Clear history", role: .destructive) {
                    UsageLog.shared.clear()
                    records = []
                    stats = UsageLog.Stats()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
    }

    private func reload() {
        records = UsageLog.shared.allRecords().reversed()
        stats = UsageLog.shared.stats()
    }

    private func statBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
