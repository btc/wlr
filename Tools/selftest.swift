import CoreGraphics
import Foundation

// End-to-end check against a *running* WLR. Drives it through the same external
// `defaults` interface a shell script would use, then reads the display LUT back from the
// WindowServer to confirm what actually reached the hardware.
//
//   make selftest
//
// The screen goes red for a few seconds while this runs. It always leaves the filter off.

let domain = "com.btc.wlr"
var failures = 0

func lut() -> (r: Float, g: Float, b: Float)? {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success, let display = ids.first
    else { return nil }
    let capacity = Int(CGDisplayGammaTableCapacity(display))
    var r = [CGGammaValue](repeating: 0, count: capacity)
    var g = [CGGammaValue](repeating: 0, count: capacity)
    var b = [CGGammaValue](repeating: 0, count: capacity)
    var produced: UInt32 = 0
    guard CGGetDisplayTransferByTable(
        display, UInt32(capacity), &r, &g, &b, &produced) == .success, produced > 1
    else { return nil }
    let top = Int(produced) - 1
    return (r[top], g[top], b[top])
}

@discardableResult
func shell(_ path: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func set(_ key: String, _ type: String, _ value: String) {
    shell("/usr/bin/defaults", ["write", domain, key, type, value])
}

/// Waits for the LUT to settle, then compares the top of each ramp against expectations.
func expect(_ label: String, r: Float, g: Float, b: Float, settle: TimeInterval = 2.0) {
    Thread.sleep(forTimeInterval: settle)
    guard let value = lut() else {
        print("  FAIL  \(label): LUT readback failed")
        failures += 1
        return
    }
    let tolerance: Float = 0.02
    let ok = abs(value.r - r) < tolerance
        && abs(value.g - g) < tolerance
        && abs(value.b - b) < tolerance
    let mark = ok ? "ok  " : "FAIL"
    print(String(format: "  %@  %-32s got r=%.3f g=%.3f b=%.3f  want r=%.3f g=%.3f b=%.3f",
                 mark, (label as NSString).utf8String!,
                 value.r, value.g, value.b, r, g, b))
    if !ok { failures += 1 }
}

guard shell("/usr/bin/pgrep", ["-x", "WLR"]) == 0 else {
    print("WLR is not running. Start it first: open /Applications/WLR.app")
    exit(2)
}

print("== WLR self-test ==")
set("transitionSeconds", "-float", "0.3")
set("intensity", "-float", "1.0")
set("redLevel", "-float", "1.0")
set("enabled", "-bool", "false")
expect("off: display untouched", r: 1.0, g: 1.0, b: 1.0)

set("enabled", "-bool", "true")
expect("on: green and blue zeroed", r: 1.0, g: 0.0, b: 0.0)

set("redLevel", "-float", "0.4")
expect("red level 0.4", r: 0.4, g: 0.0, b: 0.0)

set("intensity", "-float", "0.5")
expect("intensity 0.5: half G/B", r: 0.4, g: 0.5, b: 0.5)

set("intensity", "-float", "1.0")
set("redLevel", "-float", "1.0")
set("enabled", "-bool", "false")
expect("off again: restored", r: 1.0, g: 1.0, b: 1.0)

// The WindowServer reverts the LUT when the owning process dies. Confirm that, because
// it is the property that makes a stuck red screen recoverable.
print("== recovery ==")
set("enabled", "-bool", "true")
expect("filtering before kill", r: 1.0, g: 0.0, b: 0.0)
shell("/usr/bin/pkill", ["-KILL", "-x", "WLR"])
expect("restored after SIGKILL", r: 1.0, g: 1.0, b: 1.0, settle: 1.5)

set("enabled", "-bool", "false")
set("transitionSeconds", "-float", "2.0")
shell("/usr/bin/open", ["/Applications/WLR.app"])
Thread.sleep(forTimeInterval: 2.0)

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) FAILED")
exit(failures == 0 ? 0 : 1)
