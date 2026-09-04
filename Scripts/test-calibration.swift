// Isolated regression harness for the actual NativeScrollCalibration source.
// Run: swift -module-cache-path /private/tmp/isc-swift-cache Scripts/test-calibration.swift
// All fixtures are synthetic and temporary. No input is posted/observed,
// and no real application-support or user calibration file is accessed.
import Foundation
import Darwin

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let sourceURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/main.swift")
let temporaryURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("isc-calibration-regression-\(UUID().uuidString)", isDirectory: true)

let assertions = #"""
typealias Sample = NativeScrollCalibration.Sample
typealias RuntimeSample = NativeScrollCalibration.RuntimeSample
typealias Archive = NativeScrollCalibration.Archive
var failures: [String] = []
var checks = 0
func expect(_ condition: Bool, _ description: String) {
    checks += 1
    if condition { print("PASS: \(description)") }
    else { failures.append(description); print("FAIL: \(description)") }
}
let fixtureDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var fixtureBytes: [URL: Data] = [:]
let system = ProcessInfo.processInfo.operatingSystemVersionString
func field(_ raw: UInt32) -> CGEventField { CGEventField(rawValue: raw)! }

// Constructors generate fixture objects only; they do not demonstrate real
// iPhone Mirroring input acceptance. No post/observe/save method is called.
func wheel(phase: Int64, momentum: Int64 = 0, delta: Int32 = 0) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                        wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    event.setIntegerValueField(.scrollWheelEventMomentumOptionPhase, value: momentum)
    return event
}
func companion(phase: Int64, delta: Double = 0, subtype: Int64 = 6) -> CGEvent {
    let event = CGEvent(source: nil)!
    event.type = CGEventType(rawValue: 29)!
    event.setIntegerValueField(field(110), value: subtype)
    event.setIntegerValueField(field(132), value: phase)
    event.setIntegerValueField(field(135), value: 1)
    event.setDoubleValueField(field(119), value: delta)
    return event
}
func gesture(sign: Int32, extraChange: Bool = false) -> [RuntimeSample] {
    var events = [companion(phase: 128), wheel(phase: 128),
                  companion(phase: 1, delta: Double(sign * 10)), wheel(phase: 1, delta: sign * 10),
                  companion(phase: 2, delta: Double(sign * 90)), wheel(phase: 2, delta: sign * 120)]
    if extraChange {
        events += [companion(phase: 2, delta: Double(sign * 50)), wheel(phase: 2, delta: sign * 60)]
    }
    events += [companion(phase: 4), wheel(phase: 4),
               wheel(phase: 0, momentum: 1, delta: sign * 70),
               wheel(phase: 0, momentum: 2, delta: sign * 30), wheel(phase: 0, momentum: 3)]
    return events.enumerated().map { RuntimeSample(offset: Double($0.offset) * 0.01, event: $0.element) }
}
func serialized(_ samples: [RuntimeSample]) -> [Sample] {
    samples.map { Sample(offset: $0.offset, data: $0.event.data! as Data) }
}
func writeFixture(_ name: String, next: [Sample], previous: [Sample] = [],
                  version: Int = 4, archiveSystem: String? = nil) throws -> URL {
    var archive = Archive(system: archiveSystem ?? system, next: next, previous: previous)
    archive.version = version
    let bytes = try JSONEncoder().encode(archive)
    let url = fixtureDirectory.appendingPathComponent(name + ".json")
    try bytes.write(to: url, options: .atomic)
    fixtureBytes[url] = bytes
    return url
}
func load(_ url: URL) -> NativeScrollCalibration { NativeScrollCalibration(fileURL: url) }
func rejected(_ name: String, samples: [Sample], version: Int = 4, archiveSystem: String? = nil) throws {
    let url = try writeFixture(name, next: samples, version: version, archiveSystem: archiveSystem)
    expect(load(url).profile(.up) == nil, "rejects \(name)")
}
func replacingEvent(_ original: [RuntimeSample], at index: Int, with event: CGEvent) -> [RuntimeSample] {
    var copy = original
    copy[index] = RuntimeSample(offset: original[index].offset, event: event)
    return copy
}
let nextNative = gesture(sign: -1)
let previousNative = gesture(sign: 1, extraChange: true)
let nextFixture = serialized(nextNative)
let previousFixture = serialized(previousNative)
expect(nextNative.count != previousNative.count, "fixture contains independently sized direction recordings")
expect(nextNative.allSatisfy { NativeScrollCalibration.isSupportedEvent($0.event) },
       "continuous wheel and subtype-6 companions are supported")
let bothURL = try writeFixture("both-directions", next: nextFixture, previous: previousFixture)
let calibration = load(bothURL)
let next = calibration.profile(.up) ?? []
let previous = calibration.profile(.down) ?? []
expect(next.count == nextFixture.count && previous.count == previousFixture.count,
       "version-4 archive loads both independent directions")
let comparisonFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1,
    .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventRawDeltaAxis1,
    .scrollWheelEventAcceleratedDeltaAxis1, .scrollWheelEventScrollPhase,
    .scrollWheelEventMomentumPhase, .scrollWheelEventMomentumOptionPhase,
    field(110), field(119), field(132), field(135)]
func identical(_ expected: [RuntimeSample], _ actual: [RuntimeSample]) -> Bool {
    expected.count == actual.count && zip(expected, actual).allSatisfy { lhs, rhs in
        lhs.offset == rhs.offset && lhs.event.type == rhs.event.type
            && comparisonFields.allSatisfy {
                lhs.event.getDoubleValueField($0) == rhs.event.getDoubleValueField($0)
                    && lhs.event.getIntegerValueField($0) == rhs.event.getIntegerValueField($0)
            }
    }
}
expect(identical(nextNative, next), "NEXT preserves types/order, offsets, deltas, and companion fields")
expect(identical(previousNative, previous), "PREVIOUS preserves its own unmodified event sequence")
let reloaded = load(bothURL)
expect(identical(nextNative, reloaded.profile(.up) ?? []) && identical(previousNative, reloaded.profile(.down) ?? []),
       "fresh initialization reloads both profiles without calibration input")
let nextOnlyURL = try writeFixture("next-only", next: nextFixture)
expect(load(nextOnlyURL).profile(.up) != nil && load(nextOnlyURL).profile(.down) == nil,
       "missing PREVIOUS remains unavailable instead of sign inversion")
let previousOnlyURL = try writeFixture("previous-only", next: [], previous: previousFixture)
expect(load(previousOnlyURL).profile(.down) != nil && load(previousOnlyURL).profile(.up) == nil,
       "missing NEXT remains unavailable instead of sign inversion")
let missingURL = fixtureDirectory.appendingPathComponent("does-not-exist.json")
expect(load(missingURL).profile(.up) == nil, "missing archive has no profile")

try rejected("old-format-v3", samples: nextFixture, version: 3)
try rejected("old-format-v2", samples: nextFixture, version: 2)
try rejected("other-macOS-version", samples: nextFixture, archiveSystem: system + "-different")
try rejected("wrong-direction", samples: previousFixture)
let keyboard = CGEvent(keyboardEventSource: nil, virtualKey: 125, keyDown: true)!
let mouse = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
for (name, forbidden) in [("keyboard-event", keyboard), ("mouse-event", mouse),
                          ("other-gesture-subtype", companion(phase: 2, subtype: 7))] {
    expect(!NativeScrollCalibration.isSupportedEvent(forbidden), "unsupported \(name) is rejected before capture")
    try rejected(name + "-archive", samples: serialized(replacingEvent(nextNative, at: 4, with: forbidden)))
}
let discrete = wheel(phase: 2, delta: -120)
discrete.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
try rejected("discrete-wheel", samples: serialized(replacingEvent(nextNative, at: 5, with: discrete)))
try rejected("missing-companions", samples: serialized(nextNative.filter { $0.event.type == .scrollWheel }))
try rejected("missing-finger-end", samples: serialized(replacingEvent(nextNative, at: 7, with: wheel(phase: 2))))
try rejected("cancelled-wheel", samples: serialized(replacingEvent(nextNative, at: 5, with: wheel(phase: 8, delta: -120))))
try rejected("out-of-order-wheel", samples: serialized(replacingEvent(nextNative, at: 1, with: wheel(phase: 4))))
try rejected("missing-momentum-end", samples: Array(nextFixture.dropLast()))
try rejected("cancelled-companion", samples: serialized(replacingEvent(nextNative, at: 4, with: companion(phase: 8))))
try rejected("missing-companion-end", samples: serialized(replacingEvent(nextNative, at: 6, with: companion(phase: 2))))
var negativeOffset = nextFixture
negativeOffset[0] = Sample(offset: -0.01, data: negativeOffset[0].data)
try rejected("negative-offset", samples: negativeOffset)
var reversedOffsets = nextFixture
reversedOffsets[5] = Sample(offset: 0, data: reversedOffsets[5].data)
try rejected("reversed-offsets", samples: reversedOffsets)
var tooLong = nextFixture
tooLong[tooLong.count - 1] = Sample(offset: 3.1, data: tooLong.last!.data)
try rejected("overlong-duration", samples: tooLong)
try rejected("invalid-event-data", samples: nextFixture.enumerated().map {
    $0.offset == 4 ? Sample(offset: $0.element.offset, data: Data([0, 1, 2])) : $0.element
})
let invalidOneURL = try writeFixture("one-direction-invalid", next: previousFixture, previous: previousFixture)
expect(load(invalidOneURL).profile(.up) == nil && load(invalidOneURL).profile(.down) != nil,
       "invalid NEXT does not prevent loading independent valid PREVIOUS")
let fixturesUnchanged = try fixtureBytes.allSatisfy { url, bytes in try Data(contentsOf: url) == bytes }
expect(fixturesUnchanged, "loading leaves all synthetic fixture files byte-for-byte unchanged")
expect(!FileManager.default.fileExists(atPath: missingURL.path), "missing archive was not created")
print("Regression result: \(checks) checks, \(failures.count) failure(s). No real calibration file or input was accessed.")
exit(failures.isEmpty ? 0 : 1)
"""#

do {
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    guard let enumStart = source.range(of: "enum SwipeDirection: String {"),
          let enumEnd = source.range(of: "\n}", range: enumStart.upperBound..<source.endIndex),
          let classStart = source.range(of: "final class NativeScrollCalibration {"),
          let classEnd = source.range(of: "\nfinal class SwipeController {", range: classStart.upperBound..<source.endIndex)
    else {
        throw NSError(domain: "CalibrationRegression", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not locate production calibration source"])
    }
    let harness = "import Foundation\nimport CoreGraphics\nimport Darwin\n"
        + source[enumStart.lowerBound..<enumEnd.upperBound] + "\n"
        + source[classStart.lowerBound..<classEnd.lowerBound] + "\n" + assertions
    try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let harnessURL = temporaryURL.appendingPathComponent("main.swift")
    let binaryURL = temporaryURL.appendingPathComponent("calibration-regression")
    try harness.write(to: harnessURL, atomically: true, encoding: .utf8)
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compiler.arguments = ["swiftc", "-module-cache-path", "/private/tmp/isc-swift-cache",
                          harnessURL.path, "-o", binaryURL.path]
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else {
        throw NSError(domain: "CalibrationRegression", code: Int(compiler.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "Regression harness compilation failed"])
    }
    let test = Process()
    test.executableURL = binaryURL
    test.arguments = [temporaryURL.path]
    try test.run()
    test.waitUntilExit()
    if test.terminationStatus != 0 {
        throw NSError(domain: "CalibrationRegression", code: Int(test.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "Regression assertions failed"])
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
