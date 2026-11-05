import SwiftUI
import AppKit
import os

let log = Logger(subsystem: "com.cleanmac.app", category: "app")

@main
struct CleanMacApp: App {
    @StateObject private var manager = CleaningModeManager()
    @StateObject private var settings = AppSettings.shared

    init() {
        DispatchQueue.main.async {
            AppSettings.apply(appearance: AppSettings.shared.appAppearance)
            // Use the generated tile as the app icon so Finder / Dock /
            // Force Quit / the About panel all show the same thing.
            NSApp.applicationIconImage = AboutIcon.image(size: 512)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(manager: manager)
        } label: {
            Image(systemName: manager.state == .locked
                  ? "lock.fill"
                  : "bubbles.and.sparkles.fill")
        }
        .menuBarExtraStyle(.menu)

        Window("CleanMac Settings", id: "settings") {
            SettingsView(settings: settings)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("About CleanMac", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct MenuContent: View {
    @ObservedObject var manager: CleaningModeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("CleanMac")
        Button(manager.state == .locked ? "Cleaning Mode active…" : "Enable Cleaning Mode") {
            manager.activate()
        }
        .disabled(manager.state != .normal)
        Divider()
        Button("Settings…") { present("settings") }
            .keyboardShortcut(",", modifiers: .command)
        Button("About CleanMac") { present("about") }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func present(_ id: String) {
        openWindow(id: id)
        // 150ms so SwiftUI has created the window AND any Space switch
        // triggered by activation has had time to settle before we look it up
        // and bring it forward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id }) {
                WindowPresenter.bringToFrontOnMainScreen(window)
            }
        }
    }
}

// MARK: - About

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: AboutIcon.image())
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)

            VStack(spacing: 4) {
                Text("CleanMac")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Keep your Mac clean. Keep your input locked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Temporarily disables your keyboard and trackpad so you can clean your Mac without accidental input.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.horizontal, 12)

            HStack(spacing: 4) {
                Text("Developed by")
                    .foregroundStyle(.secondary)
                Link("Dilkush Singh",
                     destination: URL(string: "https://www.linkedin.com/in/dilkushsingh/")!)
            }
            .font(.footnote)

            VStack(spacing: 4) {
                metaRow("Version", "\(version) (\(build))")
                metaRow("Platform", "macOS")
                metaRow("Built with", "Swift & SwiftUI")
            }
            .font(.footnote)

            Text("CleanMac processes supported keyboard and pointer events locally to temporarily suppress input during Cleaning. It does not record, store, or transmit your keystrokes or pointer activity.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Text("© 2026 Dilkush Singh. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 360)
        .background(Color(nsColor: .underPageBackgroundColor).ignoresSafeArea())
    }

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary).monospacedDigit()
        }
        .frame(maxWidth: 220)
    }
}

/// Brings a window forward on an LSUIElement app and centers it on the primary
/// display. Uses a brief `.floating` level kick so the window pops above other
/// apps' windows, then drops back to `.normal` so it behaves like a regular
/// window (focusable, hideable when the user switches apps). The app stays as
/// `.accessory` throughout — no Dock icon appears.
enum WindowPresenter {
    static func bringToFrontOnMainScreen(_ window: NSWindow) {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            var frame = window.frame
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2
            frame.origin.x = max(visible.minX, min(visible.maxX - frame.width, frame.origin.x))
            frame.origin.y = max(visible.minY, min(visible.maxY - frame.height, frame.origin.y))
            window.setFrame(frame, display: true)
        }
        window.collectionBehavior.insert(.moveToActiveSpace)

        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Drop to .normal the moment the user clicks away. This keeps the
        // window visible over fullscreen apps on open, then lets it behave
        // like a regular window (can be sent behind) after that.
        dropLevelOnResignKey(window)
    }

    private static var resignObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private static func dropLevelOnResignKey(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if let existing = resignObservers[id] {
            NotificationCenter.default.removeObserver(existing)
        }
        // Ignore didResignKey events that fire during the initial Space switch
        // / activation handshake — otherwise the window drops to .normal before
        // it has even been drawn on the destination Space.
        let armed = ArmedFlag()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { armed.value = true }

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard armed.value else { return }
            window?.level = .normal
        }
        resignObservers[id] = observer
    }

    private final class ArmedFlag { var value = false }
}

/// Generated tile icon. Replace with a real asset catalog icon when designed.
enum AboutIcon {
    static func image(size: CGFloat = 128) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .regular)
            .applying(.init(paletteColors: [.systemTeal, .systemBlue]))
        let symbol = NSImage(systemSymbolName: "bubbles.and.sparkles.fill",
                             accessibilityDescription: "CleanMac")?
            .withSymbolConfiguration(cfg) ?? NSImage()

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
            NSGradient(colors: [NSColor(white: 0.14, alpha: 1),
                                NSColor(white: 0.04, alpha: 1)])?
                .draw(in: path, angle: -90)
            let s = symbol.size
            symbol.draw(in: NSRect(
                x: (size - s.width) / 2,
                y: (size - s.height) / 2,
                width: s.width, height: s.height
            ))
            return true
        }
    }
}
