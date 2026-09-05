#!/usr/bin/env swift

import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let sourceURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/main.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)

func fail(_ message: String) -> Never {
    fputs("Playback-state regression failed: \(message)\n", stderr)
    exit(1)
}

guard let focusStart = source.range(
    of: "if ensureContentFocus && !pageContextDetector.tikTokLayout().enabled"
), let focusEnd = source.range(
    of: "if config.useScrollWheelFallback",
    range: focusStart.upperBound..<source.endIndex
) else {
    fail("could not locate the synthetic content-focus block")
}

let focusBlock = String(source[focusStart.lowerBound..<focusEnd.lowerBound])
let markerCount = focusBlock.components(
    separatedBy: "replayMarker: syntheticReplayMarker"
).count - 1
guard markerCount == 2 else {
    fail("content-focus mouse down/up must both carry the synthetic marker")
}

guard let handleStart = source.range(
    of: "private func handle(type: CGEventType, event: CGEvent)"
), let clickRouting = source.range(
    of: "if type == .leftMouseDown",
    range: handleStart.upperBound..<source.endIndex
) else {
    fail("could not locate event routing")
}

let handlePrefix = String(source[handleStart.lowerBound..<clickRouting.lowerBound])
guard handlePrefix.contains(
    "event.getIntegerValueField(.eventSourceUserData) == syntheticReplayMarker"
) else {
    fail("synthetic events must be ignored before user-click playback tracking")
}

print("Playback-state regression checks passed.")
