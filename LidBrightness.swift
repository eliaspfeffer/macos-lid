import Foundation
import CoreGraphics
import IOKit
import Darwin

// shortcut: DisplayServices is private API; recheck after major macOS upgrades.
typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

func report(_ message: String) {
    FileHandle.standardError.write(Data(("\(Date()): \(message)\n").utf8))
}

struct Snapshot: Codable {
    let display: UInt32
    let brightness: Float
}

final class Controller {
    var previous: Snapshot?
    var saved: Snapshot?
    let read: (UInt32) throws -> Float
    let write: (UInt32, Float) throws -> Void
    let persist: (Snapshot?) throws -> Void

    init(saved: Snapshot? = nil, read: @escaping (UInt32) throws -> Float,
         write: @escaping (UInt32, Float) throws -> Void,
         persist: @escaping (Snapshot?) throws -> Void) {
        self.saved = saved
        self.read = read
        self.write = write
        self.persist = persist
    }

    func tick(closed: Bool, awake: Bool, display: UInt32?) throws {
        if closed && awake {
            if saved == nil {
                guard let snapshot = previous else { return }
                // Save before dimming so a crash cannot lose the restore value.
                try persist(snapshot)
                saved = snapshot
            }
            if let snapshot = saved {
                if try read(snapshot.display) > 0.001 {
                    try write(snapshot.display, 0)
                }
            }
        } else {
            if let snapshot = saved {
                try write(snapshot.display, snapshot.brightness)
                guard abs(try read(snapshot.display) - snapshot.brightness) < 0.01 else {
                    throw NSError(domain: "Brightness restore not confirmed", code: 1)
                }
                try persist(nil)
                saved = nil
                report("Restored brightness \(snapshot.brightness)")
            }
            if !closed, let display {
                previous = Snapshot(display: display, brightness: try read(display))
            }
        }
    }
}

func selfTest() throws {
    var brightness: Float = 0.63
    var disk: Snapshot?
    var failWrite = false
    var failPersist = false
    let make = { (saved: Snapshot?) in
        Controller(saved: saved, read: { _ in brightness }, write: { _, value in
            if failWrite { throw NSError(domain: "write", code: 1) }
            brightness = value
        }, persist: { value in
            if failPersist { throw NSError(domain: "persist", code: 1) }
            disk = value
        })
    }
    let c = make(nil)
    try c.tick(closed: false, awake: true, display: 1)
    try c.tick(closed: true, awake: false, display: 1)
    precondition(brightness == 0.63 && disk == nil)
    failPersist = true
    do { try c.tick(closed: true, awake: true, display: 1); preconditionFailure() } catch {}
    precondition(brightness == 0.63 && c.saved == nil)
    failPersist = false
    try c.tick(closed: true, awake: true, display: 1)
    precondition(brightness == 0 && disk?.brightness == 0.63)
    try c.tick(closed: true, awake: true, display: nil)
    precondition(disk?.brightness == 0.63)
    let restarted = make(disk)
    failWrite = true
    do { try restarted.tick(closed: false, awake: true, display: 1); preconditionFailure() } catch {}
    precondition(disk != nil && restarted.saved != nil)
    failWrite = false
    try restarted.tick(closed: false, awake: true, display: 1)
    precondition(brightness == 0.63 && disk == nil)
    brightness = 0.28
    try restarted.tick(closed: false, awake: true, display: 1)
    try restarted.tick(closed: true, awake: true, display: nil)
    precondition(brightness == 0 && disk?.brightness == 0.28)
    try restarted.tick(closed: true, awake: false, display: nil)
    precondition(brightness == 0.28 && disk == nil)
    brightness = 0
    try restarted.tick(closed: false, awake: true, display: 1)
    try restarted.tick(closed: true, awake: true, display: 1)
    try restarted.tick(closed: false, awake: true, display: 1)
    precondition(brightness == 0 && disk == nil)
    print("PASS: normal mode, close/reopen, repeated close, restart, mode change, zero brightness, persistence/write failures")
}

if CommandLine.arguments.contains("--self-test") {
    try selfTest()
    exit(0)
}

guard let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
      let getSymbol = dlsym(framework, "DisplayServicesGetBrightness"),
      let setSymbol = dlsym(framework, "DisplayServicesSetBrightness") else {
    fatalError("DisplayServices brightness API unavailable")
}
let getBrightness = unsafeBitCast(getSymbol, to: GetBrightness.self)
let setBrightness = unsafeBitCast(setSymbol, to: SetBrightness.self)
func readBrightness(_ display: UInt32) throws -> Float {
    var value: Float = 0
    let result = getBrightness(display, &value)
    guard result == 0, value.isFinite, (0...1).contains(value) else {
        throw NSError(domain: "Read brightness", code: Int(result))
    }
    return value
}
func writeBrightness(_ display: UInt32, _ value: Float) throws {
    let result = setBrightness(display, value)
    guard result == 0 else { throw NSError(domain: "Set brightness", code: Int(result)) }
}
func builtinDisplay() -> UInt32? {
    var displays = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(32, &displays, &count) == .success else { return nil }
    return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
}
let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
guard root != 0 else { fatalError("IOPMrootDomain unavailable") }
func powerFlag(_ key: String) -> Bool? {
    IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
}
let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LidBrightness")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let stateFile = directory.appendingPathComponent("brightness.json")
let saved: Snapshot?
if FileManager.default.fileExists(atPath: stateFile.path) {
    saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: stateFile))
    guard let saved, saved.brightness.isFinite, (0...1).contains(saved.brightness) else {
        fatalError("Invalid saved brightness; leaving state untouched")
    }
} else { saved = nil }
let controller = Controller(saved: saved, read: readBrightness, write: writeBrightness, persist: { snapshot in
    if let snapshot {
        try JSONEncoder().encode(snapshot).write(to: stateFile, options: .atomic)
    } else if FileManager.default.fileExists(atPath: stateFile.path) {
        try FileManager.default.removeItem(at: stateFile)
    }
})

if CommandLine.arguments.contains("--status") {
    print("closed=\(String(describing: powerFlag("AppleClamshellState"))) awake=\(String(describing: powerFlag("SleepDisabled"))) saved=\(saved != nil)")
    if let display = builtinDisplay() { print("built-in display=\(display) brightness=\(try readBrightness(display))") }
    exit(0)
}
if CommandLine.arguments.contains("--hardware-test") {
    guard saved == nil, powerFlag("AppleClamshellState") == false, let display = builtinDisplay() else {
        fatalError("Hardware test requires open lid and no pending restore")
    }
    let before = try readBrightness(display)
    do {
        try controller.tick(closed: false, awake: true, display: display)
        try controller.tick(closed: true, awake: true, display: display)
        Thread.sleep(forTimeInterval: 0.25)
        let dimmed = try readBrightness(display)
        try controller.tick(closed: false, awake: true, display: display)
        let restored = try readBrightness(display)
        guard dimmed < 0.01, abs(restored - before) < 0.01 else {
            throw NSError(domain: "Hardware brightness mismatch", code: 1)
        }
        print("PASS hardware: before=\(before) closed=\(dimmed) restored=\(restored)")
    } catch {
        try? controller.tick(closed: false, awake: true, display: display)
        throw error
    }
    exit(0)
}
report("Started lid brightness watcher")
var lastError: String?
let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
    do {
        guard let closed = powerFlag("AppleClamshellState"), let awake = powerFlag("SleepDisabled") else {
            throw NSError(domain: "Lid/power state unavailable", code: 1)
        }
        try controller.tick(closed: closed, awake: awake, display: closed ? nil : builtinDisplay())
        lastError = nil
    } catch {
        let message = String(describing: error)
        if message != lastError { report(message); lastError = message }
    }
}
timer.tolerance = 0.05
RunLoop.main.run()
