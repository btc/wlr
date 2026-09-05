import CoreGraphics
import Foundation

// Standalone escape hatch: resets every display to its ColorSync state, needing nothing
// from the app.
//
//   /Applications/WLR.app/Contents/MacOS/wlr-restore
//
// Not normally required — macOS reverts the LUT on its own when WLR exits, verified
// down to SIGKILL. This exists for the cases it does not cover: the app wedged but alive,
// or some other piece of software (a calibrator, Night Shift, a game) having left the
// ramps somewhere strange.
//
// Worth aliasing, since you may have to type it on a screen you can barely read.

CGDisplayRestoreColorSyncSettings()

var count: UInt32 = 0
if CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 {
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    if CGGetActiveDisplayList(count, &ids, &count) == .success {
        for display in ids.prefix(Int(count)) {
            // Belt and braces: write an explicit identity ramp in case the ColorSync
            // restore was a no-op for this display.
            let capacity = Int(CGDisplayGammaTableCapacity(display))
            guard capacity > 1 else { continue }
            var ramp = [CGGammaValue](repeating: 0, count: capacity)
            for i in 0..<capacity {
                ramp[i] = CGGammaValue(i) / CGGammaValue(capacity - 1)
            }
            _ = CGSetDisplayTransferByTable(display, UInt32(capacity), ramp, ramp, ramp)
        }
    }
}

// Then hand control back to ColorSync so a calibrated profile applies again.
CGDisplayRestoreColorSyncSettings()
print("Display colors restored.")
