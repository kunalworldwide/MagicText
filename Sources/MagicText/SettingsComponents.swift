import SwiftUI

/// Card-style container used by every tab in the sidebar settings.
/// Subtle material, hairline border, generous padding. Keeps a consistent
/// visual rhythm across Backend / Local Models / Usage without pulling in a
/// full design system.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var padding: CGFloat = 14

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

/// Section header used inside the detail pane.
struct SettingsSectionHeader: View {
    var title: String
    var subtitle: String?

    // Unlabeled first parameter matches SwiftUI conventions (`Text(_:)`, `Picker(_:)`)
    // so call sites read `SettingsSectionHeader("Provider", subtitle: ...)`.
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}
