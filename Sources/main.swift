import AppKit
import CoreGraphics

/// Restore the display LUT on every exit path that can still run code.
///
/// Measured on macOS 15.7.2: the WindowServer already reverts the LUT by itself when the
/// process that set it dies, including under SIGKILL, so this is a second line of defence
/// rather than the only one. It is kept because it makes the restore immediate instead of
/// dependent on process teardown, and because that WindowServer behaviour is undocumented
/// and could change.
///
/// Calling into CoreGraphics from a signal handler is not async-signal-safe. That is an
/// accepted trade: the failure mode it guards against is a screen too red to read.
private func installEmergencyRestore() {
    let onSignal: @convention(c) (Int32) -> Void = { signalNumber in
        CGDisplayRestoreColorSyncSettings()
        signal(signalNumber, SIG_DFL)
        raise(signalNumber)
    }

    for signalNumber in [
        SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGSEGV, SIGABRT, SIGILL, SIGBUS, SIGFPE, SIGTRAP,
    ] {
        signal(signalNumber, onSignal)
    }

    atexit {
        CGDisplayRestoreColorSyncSettings()
    }
}

installEmergencyRestore()

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
