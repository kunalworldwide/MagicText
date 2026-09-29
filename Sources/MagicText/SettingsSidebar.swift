import SwiftUI
import AppKit
import MagicTextCore

/// Sidebar-driven settings UI. Matches the modern macOS pattern used by
/// System Settings, Xcode, Music: section list on the left with at-a-glance
/// badges, content on the right with generous spacing. Replaces the older
/// `TabView` chrome in `SettingsWindow.swift`.
struct SidebarSettingsView: View {
    let flow: RefineFlow

    enum Pane: String, Hashable, CaseIterable, Identifiable {
        case backend = "Cloud Backend"
        case localModels = "Local Models"
        case usage = "Usage & History"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .backend: "cloud.fill"
            case .localModels: "cpu.fill"
            case .usage: "chart.bar.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .backend: "Gateway, API key, model"
            case .localModels: "On-device MLX models"
            case .usage: "Stats and recent refinements"
            }
        }
    }

    @State private var selection: Pane? = .backend
    @State private var downloadedCount: Int = 0
    @State private var usageCount: Int = 0

    private let engine = LocalModelEngine.shared

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 540)
        .onAppear(perform: refreshBadges)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(Pane.allCases) { pane in
                    SidebarRow(pane: pane, badge: badge(for: pane))
                        .tag(Optional(pane))
                }
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("MagicText")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.vertical, 6)
                .textCase(nil)
            } footer: {
                Text(appVersion)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        switch selection {
        case .backend, .none:
            BackendTabView(flow: flow)
        case .localModels:
            LocalModelsTabView(flow: flow, onModelChange: refreshBadges)
        case .usage:
            UsageTabView(flow: flow)
        }
    }

    // MARK: - Badges

    private func badge(for pane: Pane) -> String? {
        switch pane {
        case .backend: nil
        case .localModels: downloadedCount > 0 ? "\(downloadedCount)" : nil
        case .usage: usageCount > 0 ? "\(usageCount)" : nil
        }
    }

    func refreshBadges() {
        downloadedCount = LocalModelCatalog.all.filter { engine.isDownloaded($0.id) }.count
        usageCount = UsageLog.shared.allRecords().count
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "MagicText v\(v)"
    }
}

private struct SidebarRow: View {
    let pane: SidebarSettingsView.Pane
    let badge: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.icon)
                .frame(width: 22, height: 22)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(pane.rawValue)
                    .font(.system(size: 13, weight: .medium))
                Text(pane.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary.opacity(0.7)))
            }
        }
        .padding(.vertical, 3)
    }
}
