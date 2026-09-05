import AppKit

/// Launch-at-login via a per-user LaunchAgent.
///
/// Deliberately not SMAppService: that path wants a Developer ID signature and an app in
/// /Applications, whereas this bundle is ad-hoc signed and may live anywhere. A LaunchAgent
/// plist has no such requirement and is inspectable and removable by hand.
enum LoginItem {
    static let label = "com.btc.wlr"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Path to the running executable inside the bundle.
    private static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        enabled ? enable() : disable()
    }

    private static func enable() -> Bool {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            // No KeepAlive: quitting from the menu must actually quit.
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return false
        }
        // Bootstrap so it takes effect without a logout. RunAtLoad starts a second copy,
        // which the single-instance guard in AppDelegate immediately terminates.
        launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        return true
    }

    private static func disable() -> Bool {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
        return true
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
