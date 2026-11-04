import ApplicationServices
import AppKit

enum Permissions {
    /// Returns true if the process is Accessibility-trusted. `prompt: true` triggers the system
    /// prompt the first time, which is the canonical onboarding path for CGEventTap.
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let opts: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
