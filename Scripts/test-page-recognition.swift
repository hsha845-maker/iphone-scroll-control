#!/usr/bin/env swift

import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let sourceURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/main.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)

func fail(_ message: String) -> Never {
    fputs("Page-recognition regression failed: \(message)\n", stderr)
    exit(1)
}

guard source.contains("let hasVideoActionRail = rightRailCountBoxes.count >= 3") else {
    fail("busy-background fallback must require at least three action-rail counters")
}

guard source.contains("rightRailVerticalSpread >= 0.10") else {
    fail("action-rail counters must be vertically separated")
}

guard source.contains("|| (hasHomeTab && hasVideoActionRail)") else {
    fail("Home plus the action rail must enable the video feed fallback")
}

guard source.contains("let hasHomeTab = hasBottomHomeTab || englishHome") else {
    fail("the fallback must support both Douyin and TikTok Home tabs")
}

print("Page-recognition regression checks passed.")
