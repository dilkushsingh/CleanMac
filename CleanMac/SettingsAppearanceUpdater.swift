
import SwiftUI
import AppKit

struct SettingsAppearanceUpdater: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            updateWindowAppearance(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindowAppearance(for: nsView)
        }
    }

    private func updateWindowAppearance(for view: NSView) {
        guard let window = view.window else { return }

        window.appearance = appearance.nsAppearance
    }
}
