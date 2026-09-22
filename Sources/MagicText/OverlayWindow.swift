import SwiftUI

/// The non-activating status pill shown near the mouse during a refinement.
final class OverlayWindow {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(state: RefineFlow.Phase, near point: NSPoint) {
        DispatchQueue.main.async {
            let view = PillView(phase: state)
            let hosting = NSHostingView(rootView: view)

            let size = NSSize(width: 260, height: 60)
            if let panel = self.panel {
                panel.contentView = hosting
                panel.setContentSize(size)
            } else {
                let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
                p.level = .statusBar
                p.isOpaque = false
                p.backgroundColor = .clear
                p.ignoresMouseEvents = true
                p.collectionBehavior = [.canJoinAllSpaces, .stationary]
                p.contentView = hosting
                self.panel = p
            }

            // Place below-right of the trigger point, clamped to screen.
            var origin = NSPoint(x: point.x + 16, y: point.y - 70)
            if let screen = NSScreen.main {
                origin.x = min(origin.x, screen.frame.maxX - 270)
                origin.y = max(origin.y, screen.frame.minY + 10)
            }
            self.panel?.setFrameOrigin(origin)
            self.panel?.orderFrontRegardless()
            self.scheduleHide()
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.hideWorkItem = nil
            self.panel?.orderOut(nil)
        }
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
}

struct PillView: View {
    let phase: RefineFlow.Phase

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(circleColor, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 244)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var title: String {
        switch phase {
        case .reading: "Reading selection…"
        case .refining: "Refining…"
        case .writing: "Writing…"
        case .done: "Refined ✓"
        case .failed(let reason): "Couldn't refine"
        }
    }

    private var detail: String? {
        if case .failed(let reason) = phase { return reason }
        return nil
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .reading: Image(systemName: "text.magnifyingglass")
        case .refining:
            Image(systemName: "wand.and.stars")
        case .writing: Image(systemName: "arrow.down.to.line.compact")
        case .done: Image(systemName: "checkmark").bold()
        case .failed: Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var circleColor: Color {
        switch phase {
        case .reading, .refining, .writing: Color(nsColor: .controlAccentColor)
        case .done: .green
        case .failed: .orange
        }
    }
}
