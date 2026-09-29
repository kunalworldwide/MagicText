import SwiftUI
import AppKit
import MagicTextCore

/// Download manager for local MLX models, with per-machine recommendation.
struct LocalModelsTabView: View {
    let flow: RefineFlow
    var onModelChange: () -> Void = {}

    @State private var ramGB: Int = 0
    @State private var freeGB: Double = 0
    @State private var downloading: [String: Double] = [:]   // model id -> progress 0...1
    @State private var activeBackend: String = ""
    @State private var loadError: String?
    /// Bumped when the downloaded set changes so rows re-render (isDownloaded
    /// reads the HF cache, which is not observable).
    @State private var refreshTrigger: Int = 0

    private let engine = LocalModelEngine.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                systemCard
                modelsSection
                activeCard
                if let err = loadError {
                    errorCard(err)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            ramGB = LocalModelCatalog.totalSystemMemoryGB()
            freeGB = LocalModelEngine.Memory.availableGB()
            activeBackend = UserDefaults.standard.string(forKey: "backend") ?? ""
        }
    }

    // MARK: - Cards

    private var systemCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.tint.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ramGB > 0 ? "\(ramGB) GB unified memory" : "Memory detection unavailable")
                            .font(.system(size: 14, weight: .semibold))
                        Text(freeGB > 0 ? String(format: "~%.0f GB free right now", freeGB)
                                        : "Free memory detection unavailable")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let rec = topRecommendation {
                        Label(rec.name, systemImage: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                            .help("Best quality that fits comfortably in your free memory")
                    }
                }
                if !LocalModelCatalog.supportsLocalModels() {
                    Divider()
                    Label("Local models need Apple Silicon — MLX runs on Metal.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Models", subtitle: "Download from Hugging Face — 4-bit MLX, reusable across MLX apps")
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(catalog.enumerated()), id: \.element.id) { idx, m in
                        modelRow(m)
                        if idx < catalog.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
            Text("Downloaded to ~/.cache/huggingface — shared with other MLX apps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var activeCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: activeBackend.isEmpty ? "cloud.fill" : "cpu.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(activeBackend.isEmpty ? Color.blue : Color.green)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill((activeBackend.isEmpty ? Color.blue : Color.green).opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeBackend.isEmpty ? "Cloud gateway active" : "Local model active")
                        .font(.system(size: 13, weight: .semibold))
                    Text(activeBackend.isEmpty
                         ? "Refinements go through your configured gateway"
                         : activeBackend.components(separatedBy: "/").last ?? activeBackend)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if engine.isLoading {
                    ProgressView().controlSize(.small)
                    Text("Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var catalog: [LocalModel] { LocalModelCatalog.all }

    private var topRecommendation: LocalModel? {
        LocalModelCatalog.recommendations(ramGB: ramGB).first
    }

    private func modelRow(_ m: LocalModel) -> some View {
        _ = refreshTrigger   // dependency: bumping this re-renders the rows
        let downloaded = engine.isDownloaded(m.id)
        let isTop = topRecommendation?.id == m.id
        let isActive = activeBackend == m.id
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Color.green.opacity(0.18)
                          : isTop ? Color.orange.opacity(0.16)
                          : Color.secondary.opacity(0.10))
                Image(systemName: isActive ? "checkmark.circle.fill" : "cube.transparent")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isActive ? Color.green : isTop ? Color.orange : Color.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.name).font(.system(size: 13, weight: .semibold))
                    if isTop && !downloaded {
                        Text("RECOMMENDED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.orange.opacity(0.22)))
                            .foregroundStyle(.orange)
                    }
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.green.opacity(0.22)))
                            .foregroundStyle(.green)
                    }
                }
                Text("\(m.params) · \(m.sizeGB, specifier: "%.1f") GB · needs \(m.ramNeededGB, specifier: "%.0f") GB RAM")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(m.note).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            qualityStars(m.quality)
            trailingButton(m, downloaded: downloaded)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
    }

    @ViewBuilder
    private func trailingButton(_ m: LocalModel, downloaded: Bool) -> some View {
        if let progress = downloading[m.id] {
            HStack(spacing: 6) {
                if progress <= 0 {
                    ProgressView().controlSize(.small)
                } else {
                    ProgressView(value: progress).frame(width: 80)
                }
                Text(progress <= 0 ? "…" : "\(Int(progress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 34, alignment: .trailing)
            }
        } else if downloaded {
            HStack(spacing: 6) {
                Button {
                    engine.delete(m.id)
                    if activeBackend == m.id {
                        UserDefaults.standard.set("", forKey: "backend")
                        activeBackend = ""
                    }
                    refreshTrigger += 1
                    onModelChange()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .help("Delete downloaded model")
                Button(isActive ? "In Use" : "Use") {
                    Task { await useModel(m.id) }
                }
                .controlSize(.small)
                .disabled(isActive || engine.isLoading)
            }
        } else {
            Button {
                Task { await downloadModel(m) }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .medium))
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .help("Download \(m.name) (\(m.sizeGB, specifier: "%.1f") GB)")
            .disabled(!LocalModelCatalog.supportsLocalModels() || engine.isLoading)
        }
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
            try await engine.load(id: m.id, progress: { fraction in
                Task { @MainActor in
                    downloading[m.id] = fraction
                }
            })
            UserDefaults.standard.set(m.id, forKey: "backend")
            activeBackend = m.id
            refreshTrigger += 1
            onModelChange()
        } catch {
            loadError = engine.lastError ?? error.localizedDescription
            refreshTrigger += 1
            onModelChange()
        }
    }
}

// MARK: - Usage & History tab

struct UsageTabView: View {
    let flow: RefineFlow
    @State private var records: [UsageRecord] = []
    @State private var stats: UsageLog.Stats = UsageLog.Stats()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                statsCard
                historyCard
                clearCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { reload() }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("All-time", subtitle: "Across every refinement on this Mac.")
            SettingsCard {
                HStack(spacing: 28) {
                    statBox("Refinements", "\(stats.total)")
                    statBox("Success", "\(Int(stats.successRate * 100))%")
                    statBox("Avg latency", "\(stats.avgLatencyMs) ms")
                    statBox("Characters", "\(stats.charsRefined)")
                }
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader("History", subtitle: "Last 200 refinements.")
            SettingsCard(padding: 0) {
                if records.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text("No refinements yet")
                            .font(.system(size: 13, weight: .medium))
                        Text("Select text anywhere and press \(RefineFlow.Storage.loadHotkey().displayString).")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    Table(records) {
                        TableColumn("Date") { r in
                            Text(r.date.formatted(.dateTime.month().day().hour().minute().second()))
                                .font(.system(size: 11))
                        }.width(min: 130)
                        TableColumn("App") { r in
                            Text(r.app).font(.system(size: 11))
                        }.width(min: 70)
                        TableColumn("Model") { r in
                            Text(r.model).font(.system(size: 11))
                        }.width(min: 110)
                        TableColumn("Chars") { r in
                            Text("\(r.inputChars) → \(r.outputChars)")
                                .font(.system(size: 11, design: .monospaced))
                        }.width(min: 70)
                        TableColumn("Latency") { r in
                            Text("\(r.latencyMs) ms")
                                .font(.system(size: 11, design: .monospaced))
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
            }
        }
    }

    private var clearCard: some View {
        SettingsCard {
            HStack {
                Button("Clear history", role: .destructive) {
                    UsageLog.shared.clear()
                    records = []
                    stats = UsageLog.Stats()
                }
                Spacer()
            }
        }
    }

    private func reload() {
        records = UsageLog.shared.allRecords().reversed()
        stats = UsageLog.shared.stats()
    }

    private func statBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
