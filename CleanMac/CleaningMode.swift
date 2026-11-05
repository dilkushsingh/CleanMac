import SwiftUI
import Combine
import AppKit
import ServiceManagement

enum CleaningModeState: String {
    case normal, preparing, locked, unlocking, error

    var label: String {
        switch self {
        case .normal: "Ready"
        case .preparing: "Preparing…"
        case .locked: "Cleaning Mode Active"
        case .unlocking: "Unlocking…"
        case .error: "Error — input restored"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {

    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

@MainActor
final class CleaningModeManager: ObservableObject {
    @Published private(set) var state: CleaningModeState = .normal
    @Published private(set) var unlockProgress: Double = 0
    @Published private(set) var remainingSeconds: Int = 0
    @Published var lastError: String?

    private let settings = AppSettings.shared
    private var monitor: InputEventMonitor?
    private var overlay: CleaningOverlayWindow?
    private var autoUnlockTimer: Timer?
    private var tickTimer: Timer?
    private var sleepObserver: NSObjectProtocol?

    init() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.failOpen(reason: "System sleeping") }
        }
    }


    deinit {
        if let o = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
    }

    func activate() {
        guard state == .normal else { return }
        state = .preparing
        lastError = nil

        guard Permissions.ensureAccessibility(prompt: true) else {
            state = .error
            lastError = "Accessibility permission required. Enable CleanMac in System Settings → Privacy & Security → Accessibility."
            Permissions.openAccessibilitySettings()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if self.state == .error { self.state = .normal }
            }
            return
        }

        let m = InputEventMonitor(holdDuration: settings.unlockHoldSeconds)
        m.onProgress = { [weak self] p in
            Task { @MainActor in self?.unlockProgress = p }
        }
        m.onUnlock = { [weak self] in
            Task { @MainActor in self?.unlock(reason: "gesture") }
        }
        m.onFailure = { [weak self] reason in
            Task { @MainActor in self?.failOpen(reason: reason) }
        }

        guard m.start() else {
            state = .error
            lastError = "Could not create event tap. Check Accessibility permission."
            return
        }
        monitor = m

        let o = CleaningOverlayWindow(manager: self)
        overlay = o
        o.show()

        startAutoUnlock()
        startTicker()
        state = .locked
        log.info("Cleaning Mode activated")
    }

    private func unlock(reason: String) {
        guard state == .locked else { return }
        state = .unlocking
        log.info("Unlock: \(reason, privacy: .public)")
        teardown()
        state = .normal
    }

    private func failOpen(reason: String) {
        guard state == .locked || state == .preparing else { return }
        log.error("Fail-open: \(reason, privacy: .public)")
        lastError = "CleanMac exited: \(reason)"
        teardown()
        state = .error
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.state == .error { self.state = .normal }
        }
    }

    private func teardown() {
        autoUnlockTimer?.invalidate(); autoUnlockTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        monitor?.stop(); monitor = nil
        overlay?.close(); overlay = nil
        unlockProgress = 0
        remainingSeconds = 0
    }

    private func startAutoUnlock() {
        // Snapshot at activation — changes mid-lock do NOT restart the timer.
        let secs = settings.autoUnlockSeconds
        remainingSeconds = secs
        autoUnlockTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secs), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.unlock(reason: "auto-timeout") }
        }
    }

    private func startTicker() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remainingSeconds > 0 { self.remainingSeconds -= 1 }
            }
        }
    }
}

// MARK: - Settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // Bounds
    static let autoUnlockRange: ClosedRange<Int> = 60...300   // 1 min … 5 min
    static let autoUnlockStep: Int = 30
    static let holdRange: ClosedRange<Double> = 2.0...5.0
    static let holdStep: Double = 0.5
    static let autoUnlockDefault: Int = 120
    static let holdDefault: Double = 3.0

    @Published var autoUnlockSeconds: Int {
        didSet {
            let v = Self.normalizeAutoUnlock(autoUnlockSeconds)
            if v != autoUnlockSeconds { autoUnlockSeconds = v; return }
            d.set(v, forKey: "autoUnlockSeconds")
        }
    }
    @Published var unlockHoldSeconds: Double {
        didSet {
            let v = Self.normalizeHold(unlockHoldSeconds)
            if v != unlockHoldSeconds { unlockHoldSeconds = v; return }
            d.set(v, forKey: "unlockHoldSeconds")
        }
    }
    @Published var appAppearance: AppAppearance {
        didSet {
            d.set(appAppearance.rawValue, forKey: "appAppearance")
            Self.apply(appearance: appAppearance)
        }
    }

    /// Single source of truth for appearance propagation. Setting
    /// `NSApp.appearance` cascades to every window (Settings, About, overlay)
    /// and `nil` correctly restores System inheritance — unlike per-window
    /// assignment, which is sticky around nil on macOS.
    static func apply(appearance: AppAppearance) {
        guard let app = NSApp else { return }
        app.appearance = appearance.nsAppearance
    }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                let svc = SMAppService.mainApp
                if launchAtLogin, svc.status != .enabled { try svc.register() }
                if !launchAtLogin, svc.status == .enabled { try svc.unregister() }
            } catch {
                log.error("launchAtLogin toggle failed: \(error.localizedDescription, privacy: .public)")
                let actual = (SMAppService.mainApp.status == .enabled)
                if actual != launchAtLogin { launchAtLogin = actual }
            }
        }
    }

    private init() {
        let rawAuto = (d.object(forKey: "autoUnlockSeconds") as? Int) ?? Self.autoUnlockDefault
        self.autoUnlockSeconds = Self.normalizeAutoUnlock(rawAuto)

        let rawHold = (d.object(forKey: "unlockHoldSeconds") as? Double) ?? Self.holdDefault
        self.unlockHoldSeconds = Self.normalizeHold(rawHold)

        let rawAppearance = (
            d.string(forKey: "appAppearance") ??
            d.string(forKey: "overlayAppearance")
        ).flatMap(AppAppearance.init(rawValue:))

        self.appAppearance = rawAppearance ?? .system

        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    static func normalizeAutoUnlock(_ v: Int) -> Int {
        let clamped = min(autoUnlockRange.upperBound, max(autoUnlockRange.lowerBound, v))
        return (clamped / autoUnlockStep) * autoUnlockStep
    }

    static func normalizeHold(_ v: Double) -> Double {
        let clamped = min(holdRange.upperBound, max(holdRange.lowerBound, v))
        return (clamped / holdStep).rounded() * holdStep
    }
}

// MARK: - Settings view



struct SettingsView: View {

    @ObservedObject var settings: AppSettings

    var body: some View {

        VStack(alignment: .leading, spacing: 17) {

            // MARK: - Launch at login

            HStack {
                Text("Launch at login")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
            }

            // MARK: - Automatic unlock

            VStack(alignment: .leading, spacing: 12) {

                Text("Automatic Unlock Time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)

                FullWidthSliderRow(
                    valueText: formatDuration(settings.autoUnlockSeconds),
                    minLabel: "1 min",
                    maxLabel: "5 min",
                    value: Binding(
                        get: { Double(settings.autoUnlockSeconds) },
                        set: {
                            settings.autoUnlockSeconds =
                                Int(($0 / Double(AppSettings.autoUnlockStep)).rounded())
                                * AppSettings.autoUnlockStep
                        }
                    ),
                    range: (Double(AppSettings.autoUnlockRange.lowerBound)...Double(AppSettings.autoUnlockRange.upperBound)),
                    step: Double(AppSettings.autoUnlockStep),
                    defaultValue: Double(AppSettings.autoUnlockDefault)
                )
            }

            // MARK: - Unlock hold

            VStack(alignment: .leading, spacing: 12) {

                Text("Unlock Hold Time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)

                FullWidthSliderRow(
                    valueText: String(
                        format: "%.1f s",
                        settings.unlockHoldSeconds
                    ),
                    minLabel: "2 s",
                    maxLabel: "5 s",
                    value: Binding(
                        get: { settings.unlockHoldSeconds },
                        set: {
                            settings.unlockHoldSeconds =
                                ($0 / AppSettings.holdStep).rounded()
                                * AppSettings.holdStep
                        }
                    ),
                    range: AppSettings.holdRange,
                    step: AppSettings.holdStep,
                    defaultValue: AppSettings.holdDefault
                )
            }

            // MARK: - Overlay appearance

            VStack(alignment: .leading, spacing: 12) {

                Text("Appearance")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.leading, 4)

                AppearancePicker(value: $settings.appAppearance)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(cardBackground)
                    }
            }
        }
        .padding(20)
        .frame(width: 450)
        .background {
            Color(nsColor: .underPageBackgroundColor)
                .ignoresSafeArea()
        }
    }

    private var cardBackground: Color {
        Color.primary.opacity(0.07)
    }

    private func formatDuration(_ s: Int) -> String {
        let m = s / 60
        let r = s % 60

        return r == 0 ? "\(m) min" : "\(m) min \(r) s"
    }
}




struct FullWidthSliderRow: View {

    let valueText: String
    let minLabel: String
    let maxLabel: String

    @Binding var value: Double

    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double

    var body: some View {

        VStack(spacing: 4) {

            // Value and reset button

            HStack(spacing: 10) {

                Spacer()

                Text(valueText)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Button {
                    value = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }

            // Full-width slider with endpoint labels

            Slider(
                value: $value,
                in: range,
                step: step
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text(minLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            } maximumValueLabel: {
                Text(maxLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .tint(.accentColor)
            .accessibilityLabel("Adjust setting")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                }
        }
    }
}


private struct SliderRow: View {
    let valueText: String
    let minLabel: String
    let maxLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double

    private var isDefault: Bool { abs(value - defaultValue) < 0.0001 }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Spacer()
                Text(valueText)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                Button {
                    value = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
                .disabled(isDefault)
                .opacity(isDefault ? 0.35 : 1)
                .padding(.leading, 14)
            }
            Slider(value: $value, in: range) {
                EmptyView()
            } minimumValueLabel: {
                Text(minLabel).font(.caption2).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text(maxLabel).font(.caption2).foregroundStyle(.tertiary)
            }
            .tint(.accentColor)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
}

private struct AppearancePicker: View {
    @Binding var value: AppAppearance

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppAppearance.allCases) { option in
                let isSelected = value == option
                Button { value = option } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.system(size: 13))
                        Text(option.label).font(.callout)
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25),
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
