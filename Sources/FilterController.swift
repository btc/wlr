import AppKit

/// Owns the on/off state and drives the gamma engine.
///
/// Everything animates through here rather than jumping, because a hard cut to red-only is
/// jarring at night — the point of the app. When the filter reaches fully off, the engine
/// hands the LUT back to ColorSync rather than being left holding an identity ramp, so a
/// calibrated display profile still applies.
final class FilterController {
    static let didChangeState = Notification.Name("WLRFilterStateDidChange")

    private let gamma = GammaEngine()
    private let prefs = Preferences.shared

    private var animation: Timer?
    private var currentIntensity: Double = 0
    private var currentRedLevel: Double = 1
    private var engineHoldsLUT = false

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: Preferences.didChange, object: nil
        )
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(systemWoke), name: name, object: nil
            )
        }
    }

    var isOn: Bool { prefs.enabled }

    func toggle() { setOn(!prefs.enabled) }

    func setOn(_ on: Bool) {
        guard prefs.enabled != on else { return }
        prefs.enabled = on  // posts Preferences.didChange, which calls sync()
    }

    /// Apply the current preferences immediately, with no animation. Used at launch and
    /// after wake so the screen is never briefly un-filtered.
    func syncImmediately() {
        let target = targetValues()
        currentIntensity = target.intensity
        currentRedLevel = target.redLevel
        push()
    }

    @objc private func preferencesChanged() {
        sync()
        NotificationCenter.default.post(name: FilterController.didChangeState, object: nil)
    }

    @objc private func systemWoke() {
        // The LUT does not always survive a display power cycle; re-push without animating.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncImmediately()
        }
    }

    private func targetValues() -> (intensity: Double, redLevel: Double) {
        prefs.enabled ? (prefs.intensity, prefs.redLevel) : (0, 1)
    }

    private func sync() {
        let target = targetValues()
        let duration = prefs.transitionSeconds

        animation?.invalidate()
        animation = nil

        guard duration > 0.01 else {
            currentIntensity = target.intensity
            currentRedLevel = target.redLevel
            push()
            return
        }

        let startIntensity = currentIntensity
        let startRedLevel = currentRedLevel
        let startTime = Date()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startTime)
            let linear = min(1.0, elapsed / duration)
            // Smoothstep, so the ramp eases in and out rather than starting abruptly.
            let t = linear * linear * (3 - 2 * linear)
            self.currentIntensity = startIntensity + (target.intensity - startIntensity) * t
            self.currentRedLevel = startRedLevel + (target.redLevel - startRedLevel) * t
            self.push()
            if linear >= 1.0 {
                timer.invalidate()
                self.animation = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private func push() {
        let off = currentIntensity <= 0.0005 && currentRedLevel >= 0.9995
        if off {
            if engineHoldsLUT {
                gamma.restore()
                engineHoldsLUT = false
            }
            return
        }
        engineHoldsLUT = true
        gamma.apply(intensity: currentIntensity, redLevel: currentRedLevel)
    }

    /// Unconditionally return every display to its ColorSync state.
    func panicRestore() {
        animation?.invalidate()
        animation = nil
        currentIntensity = 0
        currentRedLevel = 1
        gamma.restore()
        engineHoldsLUT = false
        if prefs.enabled { prefs.enabled = false }
        NotificationCenter.default.post(name: FilterController.didChangeState, object: nil)
    }

    func shutdown() {
        animation?.invalidate()
        animation = nil
        gamma.restore()
    }
}
