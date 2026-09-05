import CoreGraphics
import Foundation

extension Notification.Name {
    static let wlrDisplaysChanged = Notification.Name("WLRDisplaysChanged")
}

/// C callback for CGDisplayRegisterReconfigurationCallback. Must be a non-capturing
/// top-level function to convert to a C function pointer.
private func displayReconfigured(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // The callback fires twice per change; ignore the "about to reconfigure" half,
    // since the LUT we write then is discarded by the reconfiguration itself.
    if flags.contains(.beginConfigurationFlag) { return }
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .wlrDisplaysChanged, object: nil)
    }
}

/// Writes the per-channel scanout LUT on every active display.
///
/// This is the lowest-level lever available without a kernel extension: the ramp is applied
/// by the display pipeline after the compositor, so it covers every window, full-screen
/// video, games, and the hardware cursor. It does not affect screenshots or screen
/// recordings, which are captured before scanout.
///
/// The LUT is process-independent state owned by the WindowServer, so two things matter:
/// other software (Night Shift, calibration tools, some games) can overwrite it — handled by
/// `watchdog` — and a crash would leave the screen tinted, handled by signal handlers in
/// `main.swift` and the bundled `wlr-restore` tool.
final class GammaEngine {
    private var watchdog: Timer?
    private var applied: (intensity: Double, redLevel: Double)?

    var isActive: Bool { applied != nil }

    init() {
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(reassert),
            name: .wlrDisplaysChanged, object: nil
        )
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// - Parameters:
    ///   - intensity: 0…1, fraction of green and blue removed.
    ///   - redLevel: 0…1, scales the red ramp so red-only output can be dimmed below the
    ///     display's own minimum backlight.
    func apply(intensity: Double, redLevel: Double) {
        applied = (intensity, redLevel)
        write(intensity: intensity, redLevel: redLevel)
        startWatchdog()
    }

    private func write(intensity: Double, redLevel: Double) {
        let gbScale = CGGammaValue(max(0, min(1, 1 - intensity)))
        let rScale = CGGammaValue(max(0, min(1, redLevel)))

        for display in GammaEngine.activeDisplays() {
            let capacity = Int(CGDisplayGammaTableCapacity(display))
            guard capacity > 1 else { continue }

            var red = [CGGammaValue](repeating: 0, count: capacity)
            var green = [CGGammaValue](repeating: 0, count: capacity)
            var blue = [CGGammaValue](repeating: 0, count: capacity)

            let denominator = CGGammaValue(capacity - 1)
            for i in 0..<capacity {
                // Identity ramp in encoded space; the panel's own EOTF still applies.
                let x = CGGammaValue(i) / denominator
                red[i] = x * rScale
                green[i] = x * gbScale
                blue[i] = x * gbScale
            }
            _ = CGSetDisplayTransferByTable(display, UInt32(capacity), red, green, blue)
        }
    }

    func restore() {
        applied = nil
        watchdog?.invalidate()
        watchdog = nil
        CGDisplayRestoreColorSyncSettings()
    }

    @objc private func reassert() {
        guard let applied else { return }
        write(intensity: applied.intensity, redLevel: applied.redLevel)
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        // Reading the LUT back is cheap, so poll rather than trying to enumerate every
        // thing that might clobber it.
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reassertIfDrifted()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func reassertIfDrifted() {
        guard let applied else { return }
        let expectedGB = CGGammaValue(max(0, min(1, 1 - applied.intensity)))
        let expectedR = CGGammaValue(max(0, min(1, applied.redLevel)))

        for display in GammaEngine.activeDisplays() {
            let capacity = Int(CGDisplayGammaTableCapacity(display))
            guard capacity > 1 else { continue }
            var red = [CGGammaValue](repeating: 0, count: capacity)
            var green = [CGGammaValue](repeating: 0, count: capacity)
            var blue = [CGGammaValue](repeating: 0, count: capacity)
            var produced: UInt32 = 0
            guard CGGetDisplayTransferByTable(
                display, UInt32(capacity), &red, &green, &blue, &produced
            ) == .success, produced > 1 else {
                reassert()
                return
            }
            let top = Int(produced) - 1
            let tolerance: CGGammaValue = 0.004
            if abs(red[top] - expectedR) > tolerance
                || abs(green[top] - expectedGB) > tolerance
                || abs(blue[top] - expectedGB) > tolerance
            {
                reassert()
                return
            }
        }
    }
}
