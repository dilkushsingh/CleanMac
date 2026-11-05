import CoreGraphics
import ApplicationServices
import Foundation

/// Testable gesture state. No I/O, no CGEvent — drive it with explicit calls.
final class UnlockGestureDetector {
    let holdDuration: Double
    private let now: () -> ContinuousClock.Instant

    private(set) var isSpacePressed = false
    private(set) var isTrackpadPressed = false
    private var startedAt: ContinuousClock.Instant?

    var onProgress: ((Double) -> Void)?
    var onUnlock: (() -> Void)?
    private var fired = false

    init(holdDuration: Double, clock: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.holdDuration = holdDuration
        self.now = clock
    }

    func space(down: Bool) {
        isSpacePressed = down
        recompute()
    }

    func trackpad(down: Bool) {
        isTrackpadPressed = down
        recompute()
    }

    /// Call periodically (e.g. 20 Hz) so progress updates even without new events.
    func tick() { recompute() }

    func reset() {
        isSpacePressed = false
        isTrackpadPressed = false
        startedAt = nil
        fired = false
        onProgress?(0)
    }

    private func recompute() {
        guard !fired else { return }
        if isSpacePressed && isTrackpadPressed {
            if startedAt == nil { startedAt = now() }
            let elapsed = startedAt!.duration(to: now()).seconds
            let p = min(1.0, max(0.0, elapsed / holdDuration))
            onProgress?(p)
            if elapsed >= holdDuration {
                fired = true
                onUnlock?()
            }
        } else {
            if startedAt != nil { onProgress?(0) }
            startedAt = nil
        }
    }
}

private extension Duration {
    var seconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}

/// Owns the CGEventTap. Callback is tight: update detector state, suppress event.
final class InputEventMonitor {
    private let detector: UnlockGestureDetector
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tickTimer: Timer?

    var onProgress: ((Double) -> Void)? {
        didSet { detector.onProgress = { [weak self] p in self?.onProgress?(p) } }
    }
    var onUnlock: (() -> Void)? {
        didSet { detector.onUnlock = { [weak self] in self?.onUnlock?() } }
    }
    var onFailure: ((String) -> Void)?

    init(holdDuration: Double) {
        self.detector = UnlockGestureDetector(holdDuration: holdDuration)
    }

    func start() -> Bool {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel,
        ]
        let mask: CGEventMask = types.reduce(0) { $0 | (1 << $1.rawValue) }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            log.error("CGEvent.tapCreate returned nil")
            return false
        }

        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = src

        // 20 Hz tick so progress advances while both inputs are held.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.detector.tick()
        }
        return true
    }

    func stop() {
        tickTimer?.invalidate(); tickTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        detector.reset()
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        case .tapDisabledByUserInput:
            onFailure?("Event tap disabled by user input")
            return nil
        case .keyDown, .keyUp:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if code == 49 { detector.space(down: type == .keyDown) }
            return nil
        case .leftMouseDown:
            detector.trackpad(down: true); return nil
        case .leftMouseUp:
            detector.trackpad(down: false); return nil
        default:
            return nil
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<InputEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type, event)
}
