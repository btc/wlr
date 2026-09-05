import Foundation

/// Turns the filter on and off on a schedule.
///
/// Edge-triggered on purpose: the schedule acts only when the answer to "should it be night
/// right now?" *changes*. That way toggling by hand mid-evening sticks until the next real
/// boundary instead of being stomped by the next timer tick.
final class Scheduler {
    private weak var controller: FilterController?
    private let prefs = Preferences.shared
    private var timer: Timer?
    private var lastDesire: Bool?

    init(controller: FilterController) {
        self.controller = controller
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: Preferences.didChange, object: nil
        )
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluate(force: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Apply the schedule's verdict right now, regardless of edges. Called at launch.
    func applyNow() {
        lastDesire = nil
        evaluate(force: true)
    }

    @objc private func preferencesChanged() {
        // Changing schedule mode or times re-establishes the baseline.
        if prefs.schedule == .manual {
            lastDesire = nil
        }
    }

    /// True when the current time falls inside the scheduled "night" window.
    func shouldBeOn(at date: Date = Date()) -> Bool? {
        switch prefs.schedule {
        case .manual:
            return nil
        case .fixed:
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: date)
            let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let on = ((prefs.onMinutes % 1440) + 1440) % 1440
            let off = ((prefs.offMinutes % 1440) + 1440) % 1440
            if on == off { return false }
            if on < off {
                return now >= on && now < off
            }
            // Window wraps midnight, e.g. 20:00 → 07:00.
            return now >= on || now < off
        case .solar:
            return Solar.isNight(
                at: date, latitude: prefs.latitude, longitude: prefs.longitude)
        }
    }

    private func evaluate(force: Bool) {
        guard let desire = shouldBeOn() else {
            lastDesire = nil
            return
        }
        if force || desire != lastDesire {
            lastDesire = desire
            controller?.setOn(desire)
        }
    }

    /// Human-readable summary for the menu.
    func statusDescription() -> String {
        switch prefs.schedule {
        case .manual:
            return "Manual"
        case .fixed:
            return "\(formatMinutes(prefs.onMinutes)) – \(formatMinutes(prefs.offMinutes))"
        case .solar:
            guard let events = Solar.events(
                date: Date(), latitude: prefs.latitude, longitude: prefs.longitude)
            else { return "Sunset – Sunrise" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Sunset \(formatter.string(from: events.sunset)) – "
                + "Sunrise \(formatter.string(from: events.sunrise))"
        }
    }
}
