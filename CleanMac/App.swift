import SwiftUI
import AppKit
import os

let log = Logger(subsystem: "com.cleanmac.app", category: "app")

@main
struct CleanMacApp: App {
    @StateObject private var manager = CleaningModeManager()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(manager: manager)
                .preferredColorScheme(settings.appAppearance.colorScheme)
        } label: {
            Image(systemName: manager.state == .locked
                  ? "lock.fill"
                  : "bubbles.and.sparkles.fill")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: settings)
        }

        Window("About CleanMac", id: "about") {
            AboutView()
                .preferredColorScheme(settings.appAppearance.colorScheme)
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
        SettingsLink { Text("Settings…") }
        Button("About CleanMac") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "about")
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
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
        .onAppear {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.identifier?.rawValue == "about" }?
                    .orderFrontRegardless()
            }
        }
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
