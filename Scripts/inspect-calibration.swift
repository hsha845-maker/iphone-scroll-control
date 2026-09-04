// Read-only: inspect saved scroll calibration without posting or recording input.
// Compile: swiftc Scripts/inspect-calibration.swift -o /tmp/inspect-calibration
// Run: /tmp/inspect-calibration '/path/to/TikTokScrollCalibration.json' [comparison.json]
import CoreGraphics
import Foundation
import Darwin

private struct Sample: Decodable {
    let offset: TimeInterval
    let data: Data
}

private struct Archive: Decodable {
    let version: Int?
    let next: [Sample]
    let previous: [Sample]
}

// Public CGEventField IDs in the macOS SDK, plus only the explicitly known
// companion fields used by the v4 recorder. Never inspect opaque event payloads.
private let publicFieldIDs: [UInt32] = Array(0...45)
    + [88, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 123,
       170, 171, 173, 175, 176, 177, 178]
private let companionEventType: UInt32 = 29
private let companionFieldIDs: [UInt32] = [110, 116, 119, 132]
private let companionSubtype = CGEventField(rawValue: 110)!
private let companionValue119 = CGEventField(rawValue: 119)!
private let companionPhase132 = CGEventField(rawValue: 132)!

private func isSupportedEvent(_ event: CGEvent) -> Bool {
    if event.type == .scrollWheel {
        return event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    }
    return event.type.rawValue == companionEventType
        && event.getIntegerValueField(companionSubtype) == 6
}

private func comparisonFieldIDs(_ events: CGEvent...) -> [UInt32] {
    publicFieldIDs + (events.contains { $0.type.rawValue == companionEventType }
                     ? companionFieldIDs : [])
}

private func histogram(_ values: [Int64]) -> String {
    let groups = Dictionary(grouping: values, by: { $0 })
    return groups.keys.sorted().map { "\($0):\(groups[$0]!.count)" }.joined(separator: ", ")
}

private func equalDouble(_ lhs: Double, _ rhs: Double) -> Bool {
    lhs == rhs || (lhs.isNaN && rhs.isNaN)
}

private func inspect(_ samples: [Sample], name: String) throws {
    guard samples.count <= 2_000 else {
        throw NSError(domain: "InspectCalibration", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Too many events in \(name)"])
    }
    var events: [CGEvent] = []
    for (index, sample) in samples.enumerated() {
        guard sample.offset.isFinite, sample.data.count < 65_536,
              let event = CGEvent(withDataAllocator: nil, data: sample.data as CFData),
              isSupportedEvent(event) else {
            throw NSError(domain: "InspectCalibration", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid continuous wheel/scroll companion event \(name)[\(index)]"])
        }
        events.append(event)
    }
    let wheelEvents = events.filter { $0.type == .scrollWheel }
    let companionEvents = events.filter { $0.type.rawValue == companionEventType }
    print("\(name): events=\(events.count), wheel=\(wheelEvents.count), companion=\(companionEvents.count)")
    guard !events.isEmpty else { return }
    for (label, field) in [
        ("phase", CGEventField.scrollWheelEventScrollPhase),
        ("momentum", .scrollWheelEventMomentumPhase),
        ("momentumOption", .scrollWheelEventMomentumOptionPhase),
        ("continuous", .scrollWheelEventIsContinuous)
    ] {
        print("  wheel \(label): [\(histogram(wheelEvents.map { $0.getIntegerValueField(field) }))]")
    }
    func stages(_ event: CGEvent) -> String {
        "phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)), "
            + "momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))"
    }
    if let first = wheelEvents.first, let last = wheelEvents.last {
        print("  wheel first: \(stages(first)); last: \(stages(last))")
    }
    if !companionEvents.isEmpty {
        print("  companion field[132] phases: [\(histogram(companionEvents.map { $0.getIntegerValueField(companionPhase132) }))]")
        let value119 = companionEvents.reduce(0.0) { $0 + $1.getDoubleValueField(companionValue119) }
        print(String(format: "  companion field[119] sum: %.6f", value119))
    }
    let axes: [(String, CGEventField, CGEventField)] = [
        ("point", .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
        ("line", .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
        ("raw", .scrollWheelEventRawDeltaAxis1, .scrollWheelEventRawDeltaAxis2),
        ("accelerated", .scrollWheelEventAcceleratedDeltaAxis1, .scrollWheelEventAcceleratedDeltaAxis2)
    ]
    for (label, verticalField, horizontalField) in axes {
        let vertical = wheelEvents.reduce(0.0) { $0 + $1.getDoubleValueField(verticalField) }
        let horizontal = wheelEvents.reduce(0.0) { $0 + $1.getDoubleValueField(horizontalField) }
        print(String(format: "  %@ sum: vertical=%.6f, horizontal=%.6f", label, vertical, horizontal))
    }
    for (name, group) in [
        ("finger", wheelEvents.filter {
            $0.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
                && $0.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
        }),
        ("momentum", wheelEvents.filter {
            $0.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        })
    ] {
        print("  \(name): events=\(group.count)")
        for (label, verticalField, horizontalField) in axes where label != "line" {
            let vertical = group.reduce(0.0) { $0 + $1.getDoubleValueField(verticalField) }
            let horizontal = group.reduce(0.0) { $0 + $1.getDoubleValueField(horizontalField) }
            print(String(format: "    %@ sum: vertical=%.6f, horizontal=%.6f", label, vertical, horizontal))
        }
    }
    let intervals = zip(samples.dropFirst(), samples).map { $0.offset - $1.offset }
    let sorted = intervals.sorted()
    if !sorted.isEmpty {
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let p95 = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        print(String(format: "  offsets: duration=%.6fs, min=%.6fs, mean=%.6fs, median=%.6fs, p95=%.6fs, max=%.6fs, negative=%d",
                     samples.last!.offset - samples.first!.offset,
                     sorted.first!, mean, sorted[sorted.count / 2], p95, sorted.last!,
                     intervals.filter { $0 < 0 }.count))
    }

    var differingEvents = 0
    var differingFields: [String: Int] = [:]
    for event in events {
        guard let data = event.data,
              let roundTrip = CGEvent(withDataAllocator: nil, data: data) else {
            throw NSError(domain: "InspectCalibration", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not round-trip a \(name) event"])
        }
        var differences: [String] = []
        if event.type != roundTrip.type { differences.append("type") }
        if event.timestamp != roundTrip.timestamp { differences.append("timestamp") }
        if event.flags != roundTrip.flags { differences.append("flags") }
        if event.location != roundTrip.location { differences.append("location") }
        if event.unflippedLocation != roundTrip.unflippedLocation { differences.append("unflippedLocation") }
        for raw in comparisonFieldIDs(event) {
            guard let field = CGEventField(rawValue: raw) else { continue }
            if event.getIntegerValueField(field) != roundTrip.getIntegerValueField(field) {
                differences.append("field[\(raw)].integer")
            }
            if !equalDouble(event.getDoubleValueField(field), roundTrip.getDoubleValueField(field)) {
                differences.append("field[\(raw)].double")
            }
        }
        if !differences.isEmpty { differingEvents += 1 }
        for difference in differences { differingFields[difference, default: 0] += 1 }
    }
    print("  serialization round-trip: differingEvents=\(differingEvents)/\(events.count), publicFieldsChecked=\(publicFieldIDs.count), extraFieldsForType29=\(companionFieldIDs)")
    for field in differingFields.keys.sorted() {
        print("    \(field): differingEvents=\(differingFields[field]!)")
    }
}

private func readArchive(_ path: String) throws -> Archive {
    let url = URL(fileURLWithPath: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber, size.int64Value <= 8_388_608 else {
        throw NSError(domain: "InspectCalibration", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "Calibration exceeds the 8 MiB inspection limit"])
    }
    return try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
}

private func compare(_ lhs: [Sample], _ rhs: [Sample], name: String) {
    print("COMPARE \(name): original=\(lhs.count), observed=\(rhs.count)")
    guard lhs.count == rhs.count else {
        print("  Event counts differ; not assuming an event-by-event alignment.")
        return
    }
    let scrollFieldIDs: Set<UInt32> = [11, 12, 13, 14, 88, 93, 94, 95, 96, 97, 98,
                                      99, 100, 123, 173, 175, 176, 177, 178]
    var changes: [String: Int] = [:]
    var flagTransitions: [String: Int] = [:]
    var changedScrollEvents = 0
    var matchedWheelPairs = 0
    var changedCompanionEvents = 0
    var matchedCompanionPairs = 0
    for (left, right) in zip(lhs, rhs) {
        guard let original = CGEvent(withDataAllocator: nil, data: left.data as CFData),
              let observed = CGEvent(withDataAllocator: nil, data: right.data as CFData) else { continue }
        var scrollChanged = false
        var companionChanged = false
        let bothWheels = original.type == .scrollWheel && observed.type == .scrollWheel
        let bothCompanions = original.type.rawValue == companionEventType
            && observed.type.rawValue == companionEventType
        if bothWheels { matchedWheelPairs += 1 }
        if bothCompanions { matchedCompanionPairs += 1 }
        for raw in comparisonFieldIDs(original, observed) {
            guard let field = CGEventField(rawValue: raw) else { continue }
            let changed = original.getIntegerValueField(field) != observed.getIntegerValueField(field)
                || !equalDouble(original.getDoubleValueField(field), observed.getDoubleValueField(field))
            if changed {
                let label = companionFieldIDs.contains(raw) ? "companionField" : "publicField"
                changes["\(label)[\(raw)]", default: 0] += 1
                if bothWheels && scrollFieldIDs.contains(raw) { scrollChanged = true }
                if bothCompanions && companionFieldIDs.contains(raw) { companionChanged = true }
            }
        }
        if scrollChanged { changedScrollEvents += 1 }
        if companionChanged { changedCompanionEvents += 1 }
        if left.offset != right.offset { changes["offset", default: 0] += 1 }
        if original.timestamp != observed.timestamp { changes["timestamp", default: 0] += 1 }
        if original.location != observed.location { changes["location", default: 0] += 1 }
        if original.unflippedLocation != observed.unflippedLocation { changes["unflippedLocation", default: 0] += 1 }
        if original.flags != observed.flags {
            changes["flags", default: 0] += 1
            let transition = String(format: "0x%llx -> 0x%llx", original.flags.rawValue, observed.flags.rawValue)
            flagTransitions[transition, default: 0] += 1
        }
        if original.type != observed.type { changes["type", default: 0] += 1 }
    }
    print("  Wheel scroll fields: differingEvents=\(changedScrollEvents)/\(matchedWheelPairs) aligned wheel pairs")
    print("  Companion fields \(companionFieldIDs): differingEvents=\(changedCompanionEvents)/\(matchedCompanionPairs) aligned companion pairs")
    for field in changes.keys.sorted() {
        print("  \(field): differingEvents=\(changes[field]!)")
    }
    for transition in flagTransitions.keys.sorted() {
        print("  flags \(transition): events=\(flagTransitions[transition]!)")
    }
    if let originalStart = lhs.first?.offset, let originalEnd = lhs.last?.offset,
       let observedStart = rhs.first?.offset, let observedEnd = rhs.last?.offset {
        let originalDuration = originalEnd - originalStart
        let observedDuration = observedEnd - observedStart
        let increase = originalDuration > 0 ? 100 * (observedDuration / originalDuration - 1) : 0
        print(String(format: "  Delivery duration: original=%.6fs, observed=%.6fs, difference=%+.6fs (%+.2f%%)",
                     originalDuration, observedDuration, observedDuration - originalDuration, increase))
    }
}

guard (2...3).contains(CommandLine.arguments.count) else {
    fputs("Usage: inspect-calibration /path/to/TikTokScrollCalibration.json [comparison.json]\n", stderr)
    exit(2)
}
do {
    let archive = try readArchive(CommandLine.arguments[1])
    print("Archive version: \(archive.version.map(String.init) ?? "unspecified")")
    try inspect(archive.next, name: "NEXT")
    try inspect(archive.previous, name: "PREVIOUS")
    if CommandLine.arguments.count == 3 {
        let comparison = try readArchive(CommandLine.arguments[2])
        print("Comparison archive version: \(comparison.version.map(String.init) ?? "unspecified")")
        try inspect(comparison.next, name: "OBSERVED NEXT")
        try inspect(comparison.previous, name: "OBSERVED PREVIOUS")
        compare(archive.next, comparison.next, name: "NEXT")
        compare(archive.previous, comparison.previous, name: "PREVIOUS")
    }
} catch {
    fputs("Inspection failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
