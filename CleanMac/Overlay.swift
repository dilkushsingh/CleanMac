import SwiftUI
import AppKit

final class CleaningOverlayWindow {
    private var windows: [NSWindow] = []
    private weak var manager: CleaningModeManager?

    init(manager: CleaningModeManager) {
        self.manager = manager
    }

    func show() {
        guard let manager else { return }

        for screen in NSScreen.screens {
            let win = NonActivatingPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            win.level = .screenSaver
            win.isOpaque = false
            win.backgroundColor = .clear
            win.ignoresMouseEvents = false
            win.hasShadow = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            // No per-window appearance — inherits from NSApp.appearance,
            // which is the single source of truth managed by AppSettings.
            win.contentView = NSHostingView(rootView: OverlayView(manager: manager))

            windows.append(win)
            win.orderFrontRegardless()
        }
    }

    func close() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct OverlayView: View {
    @ObservedObject var manager: CleaningModeManager
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("CleanMac")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Image(systemName: "lock.fill")
                    .font(.system(size: 92, weight: .light))
                    .foregroundStyle(.primary)

                VStack(spacing: 6) {
                    Text("Cleaning Mode Active")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Your keyboard and trackpad are temporarily disabled.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Text("HOW TO UNLOCK")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(2)
                    HStack(spacing: 14) {
                        KeyCap(label: "SPACE", icon: "space")
                        Text("+").font(.title2).foregroundStyle(.secondary)
                        KeyCap(label: "TRACKPAD CLICK", icon: "hand.point.up.left.fill")
                    }
                    Text("Hold both for \(settings.unlockHoldSeconds, specifier: "%.1f") seconds")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ProgressView(value: manager.unlockProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 340)
                    Text("Unlock progress: \(Int(manager.unlockProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Automatic unlock in \(format(manager.remainingSeconds))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(60)
        }
    }

    private var background: LinearGradient {
        let dark = [Color.black.opacity(0.92), Color(white: 0.08).opacity(0.92)]
        let light = [Color.white.opacity(0.92), Color(white: 0.9).opacity(0.92)]
        let colors: [Color]
        switch settings.appAppearance {
        case .dark: colors = dark
        case .light: colors = light
        case .system: colors = isSystemDark() ? dark : light
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private func format(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct KeyCap: View {
    let label: String
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(label).font(.system(.body, design: .rounded).weight(.semibold))
        }
        .padding(.vertical, 10).padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.3)))
    }
}

private func isSystemDark() -> Bool {
    NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}
