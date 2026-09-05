import Foundation

enum ScheduleMode: String {
    case manual
    case fixed
    case solar
}

/// UserDefaults-backed settings. Posts `Preferences.didChange` on every mutation so the
/// controller can re-apply without anything having to poll.
///
/// External writes count too: `defaults write com.btc.wlr enabled -bool true`
/// drives the filter from a shell script, Shortcuts action, or cron job.
final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("WLRPreferencesDidChange")

    /// Floor on `redLevel`. Deliberately not lower: red-only output is the only light left
    /// on the screen, and letting it approach zero would produce a display too dark to
    /// find the menu bar item and turn the filter back off.
    static let minimumRedLevel = 0.15

    private let store = UserDefaults.standard
    private var snapshot: [String: String] = [:]
    private var externalPoll: Timer?

    private enum Key {
        static let enabled = "enabled"
        static let intensity = "intensity"
        static let redLevel = "redLevel"
        static let schedule = "schedule"
        static let onMinutes = "onMinutes"
        static let offMinutes = "offMinutes"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let transitionSeconds = "transitionSeconds"

        static let all = [
            enabled, intensity, redLevel, schedule,
            onMinutes, offMinutes, latitude, longitude, transitionSeconds,
        ]
    }

    private init() {
        store.register(defaults: [
            Key.enabled: false,
            Key.intensity: 1.0,
            Key.redLevel: 1.0,
            Key.schedule: ScheduleMode.manual.rawValue,
            Key.onMinutes: 20 * 60,
            Key.offMinutes: 7 * 60,
            Key.latitude: 40.7128,   // New York City; overridden in the menu.
            Key.longitude: -74.0060,
            Key.transitionSeconds: 2.0,
        ])
        snapshot = currentSnapshot()
        // UserDefaults.didChangeNotification only fires for writes made by this process,
        // so an external `defaults write` would go unnoticed. Poll instead: nine small
        // reads a second is nothing, and it makes the app scriptable.
        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.detectExternalChange()
        }
        RunLoop.main.add(poll, forMode: .common)
        externalPoll = poll
    }

    private func currentSnapshot() -> [String: String] {
        var result: [String: String] = [:]
        for key in Key.all {
            result[key] = String(describing: store.object(forKey: key) ?? "")
        }
        return result
    }

    /// Compared against a snapshot so an unchanged poll costs nothing and the transition
    /// animation is never restarted needlessly.
    private func detectExternalChange() {
        let latest = currentSnapshot()
        guard latest != snapshot else { return }
        snapshot = latest
        NotificationCenter.default.post(name: Preferences.didChange, object: nil)
    }

    private func changed() {
        snapshot = currentSnapshot()
        NotificationCenter.default.post(name: Preferences.didChange, object: nil)
    }

    var enabled: Bool {
        get { store.bool(forKey: Key.enabled) }
        set { store.set(newValue, forKey: Key.enabled); changed() }
    }

    /// 0…1. How much green and blue to remove. 1 removes all of it.
    var intensity: Double {
        get { min(1, max(0, store.double(forKey: Key.intensity))) }
        set { store.set(min(1, max(0, newValue)), forKey: Key.intensity); changed() }
    }

    /// `minimumRedLevel`…1. Scales the red channel down, since red-only at full output is
    /// brighter than most people want at night.
    var redLevel: Double {
        get { min(1, max(Preferences.minimumRedLevel, store.double(forKey: Key.redLevel))) }
        set {
            let clamped = min(1, max(Preferences.minimumRedLevel, newValue))
            store.set(clamped, forKey: Key.redLevel)
            changed()
        }
    }

    var schedule: ScheduleMode {
        get { ScheduleMode(rawValue: store.string(forKey: Key.schedule) ?? "") ?? .manual }
        set { store.set(newValue.rawValue, forKey: Key.schedule); changed() }
    }

    /// Minutes past local midnight at which the filter turns on / off in `.fixed` mode.
    var onMinutes: Int {
        get { store.integer(forKey: Key.onMinutes) }
        set { store.set(newValue, forKey: Key.onMinutes); changed() }
    }

    var offMinutes: Int {
        get { store.integer(forKey: Key.offMinutes) }
        set { store.set(newValue, forKey: Key.offMinutes); changed() }
    }

    var latitude: Double {
        get { store.double(forKey: Key.latitude) }
        set { store.set(newValue, forKey: Key.latitude); changed() }
    }

    var longitude: Double {
        get { store.double(forKey: Key.longitude) }
        set { store.set(newValue, forKey: Key.longitude); changed() }
    }

    var transitionSeconds: Double {
        get { max(0, store.double(forKey: Key.transitionSeconds)) }
        set { store.set(max(0, newValue), forKey: Key.transitionSeconds); changed() }
    }
}

func formatMinutes(_ minutes: Int) -> String {
    let m = ((minutes % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", m / 60, m % 60)
}
