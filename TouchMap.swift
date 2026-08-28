// touchmap — map a USB HID touchscreen to the display it is actually attached to.
//
// macOS has no touchscreen support. A USB touch panel enumerates as a HID device
// reporting absolute coordinates, and macOS maps those coordinates onto whichever
// display currently holds the cursor. Touching an external panel therefore clicks
// somewhere on your laptop screen instead.
//
// This tool seizes the panel, converts its absolute coordinates against the target
// display's real global bounds, and posts its own mouse events there.

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import ColorSync
import ApplicationServices

// HID usage constants.
let kUsagePageGD        = 0x01   // Generic Desktop
let kUsagePageButton    = 0x09
let kUsagePageDigitizer = 0x0D
let kUsageX             = 0x30
let kUsageY             = 0x31
let kUsageTipSwitch     = 0x42
let kUsageTouchScreen   = 0x04

// ── Options ──────────────────────────────────────────────────────────────────
var optSeize        = true
var optVerbose      = false
var optDebug        = false
var optMultitouch   = false
var optProbeModes   = false
var optInvertScroll = false
var optScrollScale  = 1.0
var optHoldTime     = 0.5
var optDisplayUUID: String? = nil
var optVendor: Int? = nil
var optProduct: Int? = nil
var optListDisplays = false
var optListDevices  = false
var optStatus       = false

let VERSION      = "1.0.0"
let INSTALL_PATH = "/usr/local/bin/touchmap"
let AGENT_LABEL  = "io.github.markstrom.touchmap"

var argIt = CommandLine.arguments.dropFirst().makeIterator()

/// A flag that takes a value must actually get one, and it must parse. Silently
/// falling back to a default hides typos until someone wonders why --hold-time
/// made no difference.
func value(for flag: String) -> String {
    guard let v = argIt.next(), !v.hasPrefix("--") else {
        die("\(flag) needs a value")
    }
    return v
}

func doubleValue(for flag: String) -> Double {
    let s = value(for: flag)
    guard let d = Double(s), d.isFinite else { die("\(flag): '\(s)' is not a number") }
    return d
}

func idValue(for flag: String) -> Int {
    let s = value(for: flag)
    let parsed = (s.hasPrefix("0x") || s.hasPrefix("0X"))
        ? Int(s.dropFirst(2), radix: 16)
        : Int(s)
    guard let v = parsed else { die("\(flag): '\(s)' is not a number (use 1234 or 0x04D2)") }
    return v
}

while let a = argIt.next() {
    switch a {
    case "--no-seize":      optSeize = false
    case "-v", "--verbose": optVerbose = true
    case "--debug":         optDebug = true; optVerbose = true
    case "--multitouch":    optMultitouch = true
    case "--probe-modes":   optProbeModes = true; optMultitouch = true
    case "--invert-scroll": optInvertScroll = true
    case "--scroll-scale":  optScrollScale = doubleValue(for: a)
    case "--hold-time":     optHoldTime = doubleValue(for: a)
    case "--display":       optDisplayUUID = value(for: a)
    case "--vendor":        optVendor = idValue(for: a)
    case "--product":       optProduct = idValue(for: a)
    case "--list-displays": optListDisplays = true
    case "--list-devices":  optListDevices = true
    case "--status":        optStatus = true
    case "--version":       print("touchmap \(VERSION)"); exit(0)
    case "-h", "--help":
        print("""
        touchmap — map a USB HID touchscreen to the display it belongs to

        USAGE
          touchmap [options]

        SETUP
          --status            Check installation, permissions and hardware, then exit
          --version           Print the version and exit

        DEVICE
          --list-devices      List touchscreen-capable HID devices and exit
          --vendor <id>       Vendor ID (decimal or 0x hex). Default: auto-detect
          --product <id>      Product ID. Default: auto-detect

        DISPLAY
          --list-displays     List connected displays and exit
          --display <uuid>    Target display UUID. Default: first external display

        GESTURES
          --hold-time <sec>   Hold duration before a press becomes scroll (0.5)
          --scroll-scale <n>  Scroll speed multiplier (1.0)
          --invert-scroll     Reverse scroll direction

        DIAGNOSTICS
          -v, --verbose       Log interpreted gestures
          --debug             Log every HID report and element
          --no-seize          Do not take exclusive control of the device
          --multitouch        Try to switch the panel into multitouch mode
          --probe-modes       Write every Device Mode value and read each back
        """)
        exit(0)
    default:
        FileHandle.standardError.write("unknown argument: \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

// Validate combinations here, before any mode acts on them — otherwise a flag
// error goes unreported whenever an early-exit mode such as --list-devices runs
// first.
if (optVendor == nil) != (optProduct == nil) {
    die("--vendor and --product must be given together")
}

func log(_ s: String) { print(s); fflush(stdout) }
func die(_ s: String) -> Never {
    FileHandle.standardError.write("error: \(s)\n".data(using: .utf8)!); exit(1)
}
func hexRC(_ r: IOReturn) -> String { String(format: "0x%08X", UInt32(bitPattern: r)) }

// ── Displays ─────────────────────────────────────────────────────────────────
func displayUUID(_ id: CGDirectDisplayID) -> String? {
    guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, ref) as String?
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

if optListDisplays {
    for id in onlineDisplays() {
        let b = CGDisplayBounds(id)
        let builtin = CGDisplayIsBuiltin(id) != 0 ? "  [built-in]" : ""
        log("\(displayUUID(id) ?? "?")  \(Int(b.width))x\(Int(b.height)) @ (\(Int(b.minX)),\(Int(b.minY)))\(builtin)")
    }
    exit(0)
}

func resolveTarget() -> CGDirectDisplayID? {
    let all = onlineDisplays()
    if let want = optDisplayUUID {
        return all.first { displayUUID($0)?.caseInsensitiveCompare(want) == .orderedSame }
    }
    return all.first { CGDisplayIsBuiltin($0) == 0 }
}

final class Target {
    private(set) var bounds: CGRect = .zero
    private(set) var ok = false
    func refresh() {
        if let id = resolveTarget() {
            bounds = CGDisplayBounds(id); ok = true
            log("display: \(displayUUID(id) ?? "?")  \(Int(bounds.width))x\(Int(bounds.height)) @ (\(Int(bounds.minX)),\(Int(bounds.minY)))")
        } else {
            ok = false
            log("display: not found — touches ignored until it is connected")
            // A typo in --display would otherwise wait forever in silence.
            if optDisplayUUID != nil {
                for id in onlineDisplays() {
                    let b = CGDisplayBounds(id)
                    log("  connected: \(displayUUID(id) ?? "?")  \(Int(b.width))x\(Int(b.height))")
                }
            }
        }
    }
}
let target = Target()

// ── Device discovery ─────────────────────────────────────────────────────────
struct DeviceID { let vendor: Int; let product: Int; let name: String }

func deviceProp(_ d: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(d, key as CFString) as? Int) ?? -1
}

/// Any USB HID device whose primary usage says "touch screen". That is the class
/// of panel this tool targets: the Windows-style USB HID digitizer.
///
/// The USB filter matters. A MacBook's built-in trackpad is also a digitizer with
/// usage 0x04, reached over SPI. Without the transport check this tool could seize
/// the trackpad and leave the machine without a pointing device.
func findTouchDevices() -> [DeviceID] {
    let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(m, [
        kIOHIDPrimaryUsagePageKey: kUsagePageDigitizer,
        kIOHIDPrimaryUsageKey: kUsageTouchScreen,
    ] as CFDictionary)
    guard let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { return [] }

    var seen = Set<String>()
    var out: [DeviceID] = []
    for d in set {
        let transport = (IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String) ?? ""
        guard transport.caseInsensitiveCompare("USB") == .orderedSame else { continue }
        let v = deviceProp(d, kIOHIDVendorIDKey), p = deviceProp(d, kIOHIDProductIDKey)
        guard v > 0, p >= 0 else { continue }
        let key = "\(v):\(p)"
        if seen.insert(key).inserted {
            let name = (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "unnamed"
            out.append(DeviceID(vendor: v, product: p, name: name))
        }
    }
    return out.sorted { $0.vendor == $1.vendor ? $0.product < $1.product : $0.vendor < $1.vendor }
}

if optListDevices {
    let found = findTouchDevices()
    if found.isEmpty {
        log("no touchscreen HID devices found")
        log("(a panel must expose usage page 0x0D usage 0x04 — check it is plugged in)")
    }
    for d in found {
        log(String(format: "vendor 0x%04X  product 0x%04X  %@", d.vendor, d.product, d.name))
    }
    exit(0)
}

// ── Status ───────────────────────────────────────────────────────────────────
/// Interrogate the system directly rather than inferring state from the log.
/// IOHIDCheckAccess and AXIsProcessTrusted give definitive answers for the two
/// permissions that this tool lives or dies by.
func runningPIDs() -> [Int32] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-x", "touchmap"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let me = ProcessInfo.processInfo.processIdentifier
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\n").compactMap { Int32($0) }.filter { $0 != me }
}

if optStatus {
    let green = "\u{1B}[32m", red = "\u{1B}[31m", yellow = "\u{1B}[33m", off = "\u{1B}[0m"
    func ok(_ s: String)   { log("  \(green)ok\(off)   \(s)") }
    func bad(_ s: String)  { log("  \(red)fail\(off) \(s)") }
    func warn(_ s: String) { log("  \(yellow)note\(off) \(s)") }

    log("touchmap status")
    log("")

    let fm = FileManager.default
    let agentPath = NSHomeDirectory() + "/Library/LaunchAgents/\(AGENT_LABEL).plist"

    fm.isExecutableFile(atPath: INSTALL_PATH)
        ? ok("binary installed: \(INSTALL_PATH)")
        : bad("binary not installed at \(INSTALL_PATH) — run ./install.sh")

    fm.fileExists(atPath: agentPath)
        ? ok("starts automatically at login")
        : bad("LaunchAgent not installed — run ./install.sh")

    let pids = runningPIDs()
    pids.isEmpty
        ? bad("not running — launchctl kickstart -k gui/$UID/\(AGENT_LABEL)")
        : ok("running (pid \(pids.map(String.init).joined(separator: " ")))")

    // Permissions apply to the binary being executed, so say which one that is.
    let self_ = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    if self_ != INSTALL_PATH {
        warn("checking THIS copy (\(self_)), not the installed one.")
        warn("permissions are per-binary — run '\(INSTALL_PATH) --status' for the real answer.")
    }

    if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
        ok("Input Monitoring granted — can read the panel")
    } else {
        bad("Input Monitoring NOT granted — the panel cannot be read")
        log("       open \"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent\"")
        log("       then add \(INSTALL_PATH)")
    }

    if AXIsProcessTrusted() {
        ok("Accessibility granted — can move the cursor and click")
    } else {
        bad("Accessibility NOT granted — clicks go nowhere")
        log("       open \"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility\"")
        log("       then add \(INSTALL_PATH)")
    }

    let devices = findTouchDevices()
    if let d = devices.first {
        ok(String(format: "touchscreen: %@ (vendor 0x%04X, product 0x%04X)",
                  d.name, d.vendor, d.product))
        if devices.count > 1 { warn("\(devices.count) touchscreens present — first one is used") }
    } else {
        bad("no USB touchscreen found — is the panel plugged in?")
    }

    if let id = resolveTarget() {
        let b = CGDisplayBounds(id)
        ok("target display: \(Int(b.width))x\(Int(b.height)) @ (\(Int(b.minX)),\(Int(b.minY)))")
    } else {
        bad("no external display found")
    }

    exit(0)
}

// Resolve which panel to drive: explicit flags win, otherwise auto-detect.
let deviceID: DeviceID
if let v = optVendor, let p = optProduct {
    deviceID = DeviceID(vendor: v, product: p, name: "specified on command line")
} else {
    let found = findTouchDevices()
    guard let first = found.first else {
        die("""
            no touchscreen found.
            Run with --list-devices to see what is connected, and pass
            --vendor/--product if your panel is not detected automatically.
            """)
    }
    if found.count > 1 {
        log("note: \(found.count) touchscreens found, using the first — override with --vendor/--product")
    }
    deviceID = first
}
log(String(format: "device: %@ (vendor 0x%04X, product 0x%04X)",
           deviceID.name, deviceID.vendor, deviceID.product))

target.refresh()

CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
    if flags.contains(.setModeFlag) || flags.contains(.addFlag)
        || flags.contains(.removeFlag) || flags.contains(.desktopShapeChangedFlag) {
        target.refresh()
    }
}, nil)

// ── Gesture state ────────────────────────────────────────────────────────────
// A panel may deliver on either of two paths depending on its mode:
//   Mouse collection      button 1 + absolute X/Y   (mouse emulation)
//   Digitizer collection  TipSwitch + absolute X/Y  (per finger)
// Both are treated the same way: one "contact" per HID collection.
struct Contact {
    var x = 0, y = 0
    var xMax = 0, yMax = 0
    var down = false
    var hasPos: Bool { xMax > 0 && yMax > 0 }
}
var contacts: [UInt32: Contact] = [:]

enum Phase { case idle, pending, dragging, scrolling }
var phase: Phase = .idle

var lastPt = CGPoint.zero        // latest finger position, global coordinates
var touchStart = CGPoint.zero    // where the finger first landed
var touchStartAt: TimeInterval = 0
var scrollAnchor = CGPoint.zero  // point we last scrolled from
var lastUpPt = CGPoint.zero
var lastDownAt: TimeInterval = 0
var clickState = 1

let MOVE_SLOP = 8.0              // how far a finger may drift and still count as still

func nowTS() -> TimeInterval { Date().timeIntervalSince1970 }

func post(_ type: CGEventType, _ p: CGPoint) {
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                          mouseCursorPosition: p, mouseButton: .left) else { return }
    e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
    e.post(tap: .cghidEventTap)
}

func postScroll(_ dx: Double, _ dy: Double) {
    let sign = optInvertScroll ? -1.0 : 1.0
    let vy = Int32((sign * dy * optScrollScale).rounded())
    let vx = Int32((sign * dx * optScrollScale).rounded())
    guard vx != 0 || vy != 0 else { return }
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                          wheelCount: 2, wheel1: vy, wheel2: vx, wheel3: 0) else { return }
    e.post(tap: .cghidEventTap)
    if optVerbose { log("scroll \(vx),\(vy)") }
}

func updateClickState(_ p: CGPoint) {
    let t = nowTS()
    let near = hypot(p.x - lastUpPt.x, p.y - lastUpPt.y) < 12
    clickState = (t - lastDownAt < 0.45 && near) ? min(clickState + 1, 3) : 1
    lastDownAt = t
}

/// Called every 50 ms. A finger held still produces no value changes and therefore
/// no HID callbacks, so the transition into scroll mode has to be timer-driven.
func checkHold() {
    guard phase == .pending,
          nowTS() - touchStartAt >= optHoldTime,
          hypot(lastPt.x - touchStart.x, lastPt.y - touchStart.y) <= MOVE_SLOP
    else { return }
    // The button has been down since touch-down; release it before scrolling.
    post(.leftMouseUp, lastPt)
    lastUpPt = lastPt
    phase = .scrolling
    scrollAnchor = lastPt
    if optVerbose { log("scroll mode  \(Int(lastPt.x)),\(Int(lastPt.y))") }
}

func emit() {
    guard target.ok else { return }
    let b = target.bounds

    let downs = contacts.values.filter { $0.down && $0.hasPos }

    // ── All fingers lifted ───────────────────────────────────────────────────
    if downs.isEmpty {
        switch phase {
        case .pending, .dragging:
            post(.leftMouseUp, lastPt)
            lastUpPt = lastPt
            if optVerbose { log("up    \(Int(lastPt.x)),\(Int(lastPt.y))") }
        case .scrolling, .idle:
            break   // button was already released when scroll mode engaged
        }
        phase = .idle
        return
    }

    // ── Two or more fingers: scroll directly ─────────────────────────────────
    // Panels stuck in mouse emulation never report more than one contact, but
    // this branch costs nothing and is correct for hardware that does.
    if downs.count >= 2 {
        if phase == .dragging || phase == .pending { post(.leftMouseUp, lastPt) }
        let cx = downs.map { Double($0.x) / Double($0.xMax) }.reduce(0, +) / Double(downs.count)
        let cy = downs.map { Double($0.y) / Double($0.yMax) }.reduce(0, +) / Double(downs.count)
        let p = CGPoint(x: b.minX + cx * b.width, y: b.minY + cy * b.height)
        if phase == .scrolling { postScroll(p.x - scrollAnchor.x, p.y - scrollAnchor.y) }
        phase = .scrolling
        scrollAnchor = p
        lastPt = p
        return
    }

    // ── One finger ───────────────────────────────────────────────────────────
    guard let c = downs.first else { return }
    let p = CGPoint(x: b.minX + (Double(c.x) / Double(c.xMax)) * b.width,
                    y: b.minY + (Double(c.y) / Double(c.yMax)) * b.height)

    switch phase {
    case .idle:
        // Press the button on touch-down. Deferring it to lift-off produced a
        // zero-duration click that applications silently ignored.
        phase = .pending
        touchStart = p
        touchStartAt = nowTS()
        lastPt = p
        updateClickState(p)
        post(.leftMouseDown, p)
        if optVerbose { log("down  \(Int(p.x)),\(Int(p.y))  click=\(clickState)") }

    case .pending:
        // The button is already down, so the event is the same either way; passing
        // MOVE_SLOP only decides that this is a drag and not a candidate for the
        // hold-to-scroll timer.
        lastPt = p
        if hypot(p.x - touchStart.x, p.y - touchStart.y) > MOVE_SLOP {
            phase = .dragging
            if optVerbose { log("drag  \(Int(p.x)),\(Int(p.y))") }
        }
        post(.leftMouseDragged, p)

    case .dragging:
        lastPt = p
        post(.leftMouseDragged, p)

    case .scrolling:
        lastPt = p
        postScroll(p.x - scrollAnchor.x, p.y - scrollAnchor.y)
        scrollAnchor = p
    }
}

// ── HID ──────────────────────────────────────────────────────────────────────
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

// Match ALL collections on the device. A panel in mouse-emulation mode delivers
// on the Mouse collection, not the digitizer one.
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey: deviceID.vendor,
    kIOHIDProductIDKey: deviceID.product,
] as CFDictionary)

// Windows Digitizer "Device Configuration": report ID 33 = { Device Mode, Device Index }.
// Mode 2 requests multitouch. Many cheap controllers acknowledge the write and
// then ignore it — use --probe-modes to find out whether yours stores anything.
func readDeviceMode(_ device: IOHIDDevice) -> String {
    var back = [UInt8](repeating: 0, count: 8)
    var len = back.count
    let g = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 33, &back, &len)
    guard g == kIOReturnSuccess else { return "read failed \(hexRC(g))" }
    return back.prefix(max(len, 1)).map { String($0) }.joined(separator: ",")
}

@discardableResult
func setDeviceMode(_ device: IOHIDDevice, _ mode: UInt8) -> IOReturn {
    var withoutID: [UInt8] = [mode, 0x00]
    var r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 33, &withoutID, withoutID.count)
    if r != kIOReturnSuccess {
        var withID: [UInt8] = [33, mode, 0x00]
        r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 33, &withID, withID.count)
    }
    return r
}

func probeModes(_ device: IOHIDDevice) {
    log("  Device Mode before: \(readDeviceMode(device))")
    for mode in [UInt8(0), 1, 2, 3] {
        let r = setDeviceMode(device, mode)
        log("  wrote mode \(mode): \(hexRC(r)) → reads back: \(readDeviceMode(device))")
    }
    setDeviceMode(device, 2)
    log("  restored to mode 2")
}

let valueCallback: IOHIDValueCallback = { _, _, _, value in
    let el = IOHIDValueGetElement(value)
    let page = Int(IOHIDElementGetUsagePage(el))
    let usage = Int(IOHIDElementGetUsage(el))
    let v = Int(IOHIDValueGetIntegerValue(value))

    if optDebug {
        let pc = IOHIDElementGetParent(el).map { String(IOHIDElementGetCookie($0)) } ?? "nil"
        log(String(format: "  val page=0x%02X usage=0x%02X val=%d parent=%@", page, usage, v, pc))
    }

    // Group by parent collection: one finger, or the mouse collection.
    guard let parent = IOHIDElementGetParent(el) else { return }
    let key = IOHIDElementGetCookie(parent)
    var c = contacts[key] ?? Contact()

    switch (page, usage) {
    // Contact down: TipSwitch (digitizer) or button 1 (mouse emulation).
    case (kUsagePageDigitizer, kUsageTipSwitch), (kUsagePageButton, 0x01):
        c.down = (v != 0)
        contacts[key] = c
        emit()

    case (kUsagePageGD, kUsageX):
        if IOHIDElementIsRelative(el) { return }   // a real relative mouse, not our panel
        c.x = v
        c.xMax = Int(IOHIDElementGetLogicalMax(el))
        contacts[key] = c
        if c.down { emit() }

    case (kUsagePageGD, kUsageY):
        if IOHIDElementIsRelative(el) { return }
        c.y = v
        c.yMax = Int(IOHIDElementGetLogicalMax(el))
        contacts[key] = c
        if c.down { emit() }

    default:
        return
    }
}

IOHIDManagerRegisterInputValueCallback(manager, valueCallback, nil)

var rawBufs: [UnsafeMutablePointer<UInt8>] = []

IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let page = deviceProp(device, kIOHIDPrimaryUsagePageKey)
    let usage = deviceProp(device, kIOHIDPrimaryUsageKey)
    let name: String
    switch (page, usage) {
    case (0x01, 0x02): name = "Mouse"
    case (0x0D, 0x04): name = "TouchScreen digitizer"
    default:           name = "vendor/other"
    }
    log(String(format: "collection: %@ (page=0x%02X usage=0x%02X)", name, page, usage))

    if page == kUsagePageDigitizer {
        if optProbeModes {
            probeModes(device)
        } else if optMultitouch {
            let r = setDeviceMode(device, 2)
            log(r == kIOReturnSuccess
                ? "  multitouch requested (Device Mode = 2), stored value: \(readDeviceMode(device))"
                : "  could not set Device Mode (\(hexRC(r)))")
        }
    }

    if optDebug {
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        rawBufs.append(buf)
        IOHIDDeviceRegisterInputReportCallback(device, buf, 1024, { _, _, _, _, reportID, report, length in
            var hex = ""
            for i in 0..<min(Int(length), 24) { hex += String(format: "%02X ", report[i]) }
            log("  raw id=\(reportID) len=\(length): \(hex)")
        }, nil)
    }
}, nil)

IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in
    log("touch panel disconnected")
    if phase == .dragging || phase == .pending { post(.leftMouseUp, lastPt) }
    contacts.removeAll()
    phase = .idle
}, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let rc = IOHIDManagerOpen(manager, IOOptionBits(optSeize ? kIOHIDOptionsTypeSeizeDevice
                                                         : kIOHIDOptionsTypeNone))
if rc != kIOReturnSuccess {
    if UInt32(bitPattern: rc) == 0xE00002C5 {
        die("""
            device is already held exclusively by another process (\(hexRC(rc))).
            An earlier touchmap is probably still running:
                pkill -x touchmap
            """)
    }
    if optSeize {
        log("warning: could not take exclusive control (\(hexRC(rc))) — falling back to shared mode.")
        if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) != kIOReturnSuccess {
            die("could not open the HID device. Grant Input Monitoring in System Settings.")
        }
    } else {
        die("could not open the HID device (\(hexRC(rc))).")
    }
} else if optSeize {
    log("exclusive control of the touch panel — macOS's own mapping is disabled")
}

signal(SIGINT)  { _ in IOHIDManagerClose(manager, 0); exit(0) }
signal(SIGTERM) { _ in IOHIDManagerClose(manager, 0); exit(0) }

let holdTimer = CFRunLoopTimerCreateWithHandler(
    kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.05, 0.05, 0, 0) { _ in checkHold() }
CFRunLoopAddTimer(CFRunLoopGetCurrent(), holdTimer, .defaultMode)

log("touchmap running. Ctrl-C to stop.")
CFRunLoopRun()
