import AppKit
import ApplicationServices
import AVFoundation
import Darwin
import Foundation
import ScreenCaptureKit
import Vision

// MARK: - User configuration

struct Config {
    // Run once and watch the console before changing these if your mouse differs.
    // Logitech G309 confirmed mapping:
    // rear side button (3) -> next video; front side button (4) -> previous video.
    var nextButton: Int64 = 3
    var previousButton: Int64 = 4

    var horizontalRatio: CGFloat = 0.50
    var swipeStartRatio: CGFloat = 0.70
    var swipeEndRatio: CGFloat = 0.30
    var swipeDuration: TimeInterval = 0.20
    var swipeSteps: Int = 15
    var debounceInterval: TimeInterval = 0.60

    var enableMiddleClickPlayPause: Bool = false
    var middleButton: Int64 = 2
    var middleClickXRatio: CGFloat = 0.50
    var middleClickYRatio: CGFloat = 0.50

    // iPhone Mirroring did not accept synthetic left-button dragging on this Mac,
    // so use its documented mouse/trackpad scrolling path by default.
    var useScrollWheelFallback: Bool = true
    var scrollLineDelta: Int32 = 10
    var scrollBurstCount: Int = 18
    var scrollBurstDuration: TimeInterval = 0.24
    // TikTok needs one continuous gesture rather than independent wheel ticks.
    var tikTokScrollHeightRatio: CGFloat = 1.60
    var tikTokScrollDuration: TimeInterval = 0.25
    var tikTokWheelPaging: Bool = true
    var tikTokWheelQuietInterval: TimeInterval = 0.65
    // Change to -1 if the resulting scroll direction is reversed on your Mac.
    var scrollDirectionMultiplier: Int32 = 1

    // Uses private WindowServer APIs because macOS has no public API for
    // changing another application's window level.
    var keepMirroringWindowOnTop: Bool = false
    var alwaysOnTopRefreshInterval: TimeInterval = 1.0

    // Reliable fallback for current macOS: show a live, non-activating floating
    // preview of the iPhone Mirroring window using ScreenCaptureKit.
    var enableFloatingLivePreview: Bool = true
    var floatingPreviewFPS: Int = 30
    // The iPhone device frame is much rounder at the bottom than the macOS
    // title-bar corners at the top, so mask them independently.
    var floatingPreviewTopCornerRadius: CGFloat = 24
    var floatingPreviewBottomCornerRadius: CGFloat = 82

    // Keyboard controls are active only while the real iPhone Mirroring app is
    // frontmost. macOS virtual key codes: Down = 125, Up = 126.
    var enableArrowKeyControl: Bool = true
    var nextVideoKeyCode: Int64 = 125
    var previousVideoKeyCode: Int64 = 126
    // Some external keyboards report navigation through the numeric keypad:
    // keypad 2 = Down and keypad 8 = Up. These aliases are used only on a
    // positively recognized video page. While the share sheet is active,
    // keypad 1/2/3 still keep their recipient-selection meaning.
    var nextVideoAlternateKeyCodes: Set<Int64> = [84]
    var previousVideoAlternateKeyCodes: Set<Int64> = [91]
    var enableSpacePlayPause: Bool = true
    var playPauseKeyCode: Int64 = 49
    var pauseBeforeMinimizeOrHide: Bool = true
    var minimizeKeyCode: Int64 = 46 // Command-M
    var hideKeyCode: Int64 = 4      // Command-H
    // Give Douyin enough time to commit the pause before macOS removes the
    // mirrored surface. A very short delay can leave audio playing after hide.
    var pauseBeforeWindowActionDelay: TimeInterval = 0.35
    var enableLikeAndShareKeys: Bool = true
    var likeKeyCode: Int64 = 123       // Left Arrow
    var shareKeyCode: Int64 = 124      // Right Arrow
    var likeAlternateKeyCodes: Set<Int64> = [86]   // keypad 4
    var shareAlternateKeyCodes: Set<Int64> = [88]  // keypad 6
    // Main keyboard 1-5 and numeric-keypad 1-5.
    var shareRecipientKeyCodes: [Int64: Int] = [
        18: 0, 19: 1, 20: 2,
        21: 3, 23: 4,
        83: 0, 84: 1, 85: 2,
        86: 3, 87: 4
    ]
    var shareSelectionTimeout: TimeInterval = 30.0
    var shareButtonXRatio: CGFloat = 0.91
    var shareButtonYRatio: CGFloat = 0.74
    // Vision normally sees the counter below the share icon more reliably than
    // the icon itself. Move upward from that counter to the icon center.
    var shareIconAboveCountRatio: CGFloat = 0.033
    var shareRecipientXRatios: [CGFloat] = [0.12, 0.30, 0.48, 0.66, 0.84]
    var shareRecipientYRatio: CGFloat = 0.72
    var shareSendSingleXRatio: CGFloat = 0.50
    var shareSendMultipleXRatio: CGFloat = 0.73
    var shareSendYRatio: CGFloat = 0.92
    var shareCloseXRatio: CGFloat = 0.91
    var shareCloseYRatio: CGFloat = 0.67
    var shareSendKeyCodes: Set<Int64> = [36, 76] // Return, keypad Enter
    // Calibrated against the English TikTok iPhone share sheet (six columns).
    var tikTokShareButtonYRatio: CGFloat = 0.78
    var tikTokRecipientXRatios: [CGFloat] = [0.115, 0.28, 0.445, 0.605, 0.77]
    // Give iPhone Mirroring time to finish becoming key/frontmost before the
    // first synthetic scroll after clicking the floating preview.
    var activationSettleInterval: TimeInterval = 0.70
    var videoPageRecognitionInterval: TimeInterval = 0.45
    // OCR can miss one frame while captions animate. Window actions may still
    // use a recent positive feed result unless direct input invalidated it.
    var videoRecognitionGraceInterval: TimeInterval = 3.0
    // Selecting a recipient can collapse the share sheet into a simpler
    // “分享给 + 发送” layout. Keep a short confirmed-share grace period so
    // Enter remains reliable through that transition.
    var shareRecognitionGraceInterval: TimeInterval = 5.0
    // While the user is composing text (especially with a Chinese input
    // method), Space/arrows/numbers must reach the input method unchanged.
    var textInputProtectionInterval: TimeInterval = 2.0

    // The program always prints the real frontmost name and bundle identifier.
    // Add the printed bundle identifier here for the strictest match.
    // Confirmed at runtime on macOS: iPhone Mirroring reports this identifier.
    var allowedBundleIdentifiers: Set<String> = ["com.apple.ScreenContinuity"]

    // These localized names let the first test work before the bundle ID is known.
    var allowedApplicationNames: Set<String> = [
        "iPhone Mirroring",
        "iPhone 镜像",
        "iPhone 鏡像"
    ]
}

enum SwipeDirection: String {
    case up
    case down
}

private func pointDescription(_ point: CGPoint) -> String {
    String(format: "x: %.1f, y: %.1f", point.x, point.y)
}

private func frameDescription(_ frame: CGRect) -> String {
    String(
        format: "x: %.1f, y: %.1f, width: %.1f, height: %.1f",
        frame.origin.x, frame.origin.y, frame.width, frame.height
    )
}

// Marks events replayed by this utility so its own event tap does not process
// them a second time.
private let syntheticReplayMarker: Int64 = 0x4950_5343

private extension Notification.Name {
    static let iPhoneScrollControlWillSuspendTarget = Notification.Name(
        "iPhoneScrollControlWillSuspendTarget"
    )
}

// MARK: - iPhone Mirroring window lookup

final class IPhoneMirroringController {
    private let config: Config
    private let activationLock = NSLock()
    private var lastActivationUptime: TimeInterval?
    private let logLock = NSLock()
    private var lastLoggedApp: pid_t?

    init(config: Config) {
        self.config = config
    }

    func frontmostTargetApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            print("Frontmost app: unavailable")
            return nil
        }

        let name = app.localizedName ?? "(unknown name)"
        let bundleID = app.bundleIdentifier ?? "(no bundle identifier)"
        logLock.lock()
        let changed = lastLoggedApp != app.processIdentifier
        lastLoggedApp = app.processIdentifier
        logLock.unlock()
        if changed { print("Frontmost app:\n  \(name)\n  \(bundleID)") }

        let bundleMatches = app.bundleIdentifier.map {
            config.allowedBundleIdentifiers.contains($0)
        } ?? false
        let nameMatches = app.localizedName.map {
            config.allowedApplicationNames.contains($0)
        } ?? false

        return (bundleMatches || nameMatches) ? app : nil
    }

    func runningTargetApplication() -> NSRunningApplication? {
        for bundleID in config.allowedBundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleID
            ).first {
                return app
            }
        }

        return NSWorkspace.shared.runningApplications.first { app in
            app.localizedName.map { config.allowedApplicationNames.contains($0) } ?? false
        }
    }

    // AX can keep returning the last window frame after the application has
    // been hidden or its window has been minimized. Require both application
    // state and a real, currently on-screen WindowServer entry before treating
    // that old frame as interactive.
    func isTargetWindowInteractive(_ app: NSRunningApplication? = nil) -> Bool {
        guard let app = app ?? runningTargetApplication(), !app.isHidden else {
            return false
        }

        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        if result != .success || windowValue == nil {
            result = AXUIElementCopyAttributeValue(
                applicationElement,
                kAXMainWindowAttribute as CFString,
                &windowValue
            )
        }

        if result == .success, let windowValue {
            let window = unsafeBitCast(windowValue, to: AXUIElement.self)
            var minimizedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                &minimizedValue
            ) == .success,
            let minimized = minimizedValue as? Bool,
            minimized {
                return false
            }
        }

        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        return windows.contains { info in
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard ownerPID == app.processIdentifier, alpha > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
                return false
            }
            return frame.width * frame.height > 10_000
        }
    }

    @discardableResult
    func activateTargetApplication() -> Bool {
        guard let app = runningTargetApplication() else {
            print("Activate request: iPhone Mirroring is not running.")
            return false
        }

        activationLock.lock()
        lastActivationUptime = ProcessInfo.processInfo.systemUptime
        activationLock.unlock()

        app.unhide()
        let activated = app.activate(options: [.activateAllWindows])

        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(
            applicationElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXMainWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue {
            let window = unsafeBitCast(windowValue, to: AXUIElement.self)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                applicationElement,
                kAXFocusedWindowAttribute as CFString,
                window
            )
            AXUIElementSetAttributeValue(
                window,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
        }

        return activated
    }

    func waitForActivationToSettle() {
        activationLock.lock()
        let activationTime = lastActivationUptime
        activationLock.unlock()
        guard let activationTime else { return }

        let elapsed = ProcessInfo.processInfo.systemUptime - activationTime
        let remaining = config.activationSettleInterval - elapsed
        if remaining > 0 {
            print(String(format: "Waiting %.0f ms for iPhone Mirroring focus.", remaining * 1_000))
            usleep(useconds_t(remaining * 1_000_000))
        }
    }

    func isTextEntryFocused(in app: NSRunningApplication) -> Bool {
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else { return false }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
        let role = roleValue as? String,
        [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXSearchField",
            kAXComboBoxRole as String
        ].contains(role) {
            return true
        }

        var editableValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focusedElement,
            "AXEditable" as CFString,
            &editableValue
        ) == .success,
        let editable = editableValue as? Bool,
        editable {
            return true
        }

        return false
    }

    func focusedWindowFrame(of app: NSRunningApplication) -> CGRect? {
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )

        // Some applications expose a main window but no focused window.
        if result != .success || windowValue == nil {
            result = AXUIElementCopyAttributeValue(
                applicationElement,
                kAXMainWindowAttribute as CFString,
                &windowValue
            )
        }

        guard result == .success, let rawWindow = windowValue else {
            print("Could not obtain the focused/main iPhone Mirroring window (AX error \(result.rawValue)).")
            return nil
        }

        let window = unsafeBitCast(rawWindow, to: AXUIElement.self)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            window, kAXPositionAttribute as CFString, &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            window, kAXSizeAttribute as CFString, &sizeValue
        ) == .success,
        let rawPosition = positionValue,
        let rawSize = sizeValue,
        CFGetTypeID(rawPosition) == AXValueGetTypeID(),
        CFGetTypeID(rawSize) == AXValueGetTypeID()
        else {
            print("Could not read the iPhone Mirroring window position or size.")
            return nil
        }

        let axPosition = unsafeBitCast(rawPosition, to: AXValue.self)
        let axSize = unsafeBitCast(rawSize, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(axPosition, .cgPoint, &position),
              AXValueGetValue(axSize, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            print("The iPhone Mirroring window returned an invalid frame.")
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    func minimizeButtonFrame(of app: NSRunningApplication) -> CGRect? {
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue else { return nil }

        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        var buttonValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXMinimizeButtonAttribute as CFString,
            &buttonValue
        ) == .success,
        let buttonValue else { return nil }

        let button = unsafeBitCast(buttonValue, to: AXUIElement.self)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            button, kAXPositionAttribute as CFString, &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            button, kAXSizeAttribute as CFString, &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        let axPosition = unsafeBitCast(positionValue, to: AXValue.self)
        let axSize = unsafeBitCast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(axPosition, .cgPoint, &position),
              AXValueGetValue(axSize, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}

// MARK: - Keep the iPhone Mirroring window above ordinary windows

private typealias CGSMainConnectionIDFunction = @convention(c) () -> UInt32
private typealias CGSSetWindowLevelFunction = @convention(c) (
    UInt32, UInt32, Int32
) -> Int32

final class AlwaysOnTopController {
    private let config: Config
    private let mirroringController: IPhoneMirroringController
    private let targetLevel = CGWindowLevelForKey(.floatingWindow)
    private let normalLevel = CGWindowLevelForKey(.normalWindow)
    private var managedWindowIDs: Set<CGWindowID> = []
    private var didReportUnavailableAPI = false

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let mainConnectionID: CGSMainConnectionIDFunction?
    private let setWindowLevel: CGSSetWindowLevelFunction?

    init(config: Config, mirroringController: IPhoneMirroringController) {
        self.config = config
        self.mirroringController = mirroringController

        let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        )
        frameworkHandle = handle

        if let handle,
           let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
           let levelSymbol = dlsym(handle, "CGSSetWindowLevel") {
            mainConnectionID = unsafeBitCast(
                connectionSymbol,
                to: CGSMainConnectionIDFunction.self
            )
            setWindowLevel = unsafeBitCast(
                levelSymbol,
                to: CGSSetWindowLevelFunction.self
            )
        } else {
            mainConnectionID = nil
            setWindowLevel = nil
        }
    }

    deinit {
        if let frameworkHandle { dlclose(frameworkHandle) }
    }

    func refresh() {
        guard config.keepMirroringWindowOnTop else { return }
        guard let mainConnectionID, let setWindowLevel else {
            if !didReportUnavailableAPI {
                print("Always-on-top unavailable: WindowServer API symbols were not found.")
                didReportUnavailableAPI = true
            }
            return
        }
        guard let app = mirroringController.runningTargetApplication(),
              let windowID = largestOnScreenWindowID(for: app.processIdentifier) else {
            return
        }

        let connection = mainConnectionID()
        let result = setWindowLevel(connection, windowID, targetLevel)
        if result == 0 {
            if managedWindowIDs.insert(windowID).inserted {
                print("Always on top enabled for iPhone Mirroring window \(windowID).")
            }
        } else {
            print("Failed to set always-on-top window level (CGS error \(result)).")
        }

        // Forget windows that were destroyed and recreated.
        managedWindowIDs = managedWindowIDs.intersection(currentWindowIDs(for: app.processIdentifier))
    }

    func restoreNormalWindowLevel() {
        guard let mainConnectionID, let setWindowLevel else { return }
        let connection = mainConnectionID()
        for windowID in managedWindowIDs {
            _ = setWindowLevel(connection, windowID, normalLevel)
        }
        managedWindowIDs.removeAll()
    }

    private func largestOnScreenWindowID(for pid: pid_t) -> CGWindowID? {
        let windows = windowInformation(for: pid)
        return windows.max { lhs, rhs in
            windowArea(lhs) < windowArea(rhs)
        }.flatMap { windowNumber($0) }
    }

    private func currentWindowIDs(for pid: pid_t) -> Set<CGWindowID> {
        Set(windowInformation(for: pid).compactMap(windowNumber))
    }

    private func windowInformation(for pid: pid_t) -> [[String: Any]] {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return rawList.filter { info in
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return ownerPID == pid && alpha > 0 && windowArea(info) > 10_000
        }
    }

    private func windowNumber(_ info: [String: Any]) -> CGWindowID? {
        (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }

    private func windowArea(_ info: [String: Any]) -> CGFloat {
        guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
            return 0
        }
        return frame.width * frame.height
    }
}

// MARK: - Mirrored-page recognition

enum MirroredPageKind: String {
    case unknown
    case video
    case share
    case other
}

final class PageContextDetector {
    private let config: Config
    private let lock = NSLock()
    private var pageKind: MirroredPageKind = .unknown
    private var multipleShareSendButtonVisible = false
    private var lastAnalysisUptime: TimeInterval = 0
    private var analysisInProgress = false
    // Prevent an OCR request that began before a click/keystroke invalidation
    // from restoring a stale page classification after it finishes.
    private var contextRevision: UInt64 = 0
    private var lastConfirmedVideoUptime: TimeInterval = 0
    private var lastConfirmedShareUptime: TimeInterval = 0
    private var englishTikTok = false
    private var englishShareHeader: CGPoint?
    private var englishSendPoint: CGPoint?
    private var videoShareButtonPoint: CGPoint?
    private var videoShareButtonPointUptime: TimeInterval = 0

    func tikTokLayout() -> (enabled: Bool, header: CGPoint?, send: CGPoint?) {
        lock.lock()
        defer { lock.unlock() }
        let fresh = ProcessInfo.processInfo.systemUptime - lastAnalysisUptime < 1.5
        return (englishTikTok, fresh && pageKind == .share ? englishShareHeader : nil,
                fresh && pageKind == .share ? englishSendPoint : nil)
    }

    func detectedVideoShareButtonPoint() -> CGPoint? {
        lock.lock()
        defer { lock.unlock() }
        guard videoShareButtonPointUptime > 0,
              ProcessInfo.processInfo.systemUptime - videoShareButtonPointUptime
                <= config.videoRecognitionGraceInterval,
              pageKind == .video || lastConfirmedVideoUptime > 0 else { return nil }
        return videoShareButtonPoint
    }

    init(config: Config) {
        self.config = config
    }

    func currentPageKind() -> MirroredPageKind {
        lock.lock()
        defer { lock.unlock() }
        return pageKind
    }

    func shareUsesMultipleSendButton() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return multipleShareSendButtonVisible
    }

    func isVideoPageOrRecentlyConfirmed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pageKind == .video { return true }
        guard lastConfirmedVideoUptime > 0 else { return false }
        return ProcessInfo.processInfo.systemUptime - lastConfirmedVideoUptime
            <= config.videoRecognitionGraceInterval
    }

    func isSharePageOrRecentlyConfirmed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pageKind == .share { return true }
        if englishTikTok { return false }
        guard lastConfirmedShareUptime > 0 else { return false }
        return ProcessInfo.processInfo.systemUptime - lastConfirmedShareUptime
            <= config.shareRecognitionGraceInterval
    }

    func invalidate(reason: String) {
        lock.lock()
        let changed = pageKind != .other
        pageKind = .other
        multipleShareSendButtonVisible = false
        lastConfirmedVideoUptime = 0
        lastConfirmedShareUptime = 0
        englishShareHeader = nil
        englishSendPoint = nil
        videoShareButtonPoint = nil
        videoShareButtonPointUptime = 0
        contextRevision &+= 1
        lock.unlock()
        if changed {
            print("Mirrored-page shortcuts suspended: \(reason).")
        }
    }

    func inspect(_ sampleBuffer: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !analysisInProgress,
              now - lastAnalysisUptime >= config.videoPageRecognitionInterval else {
            lock.unlock()
            return
        }
        analysisInProgress = true
        lastAnalysisUptime = now
        let analysisRevision = contextRevision
        lock.unlock()

        defer {
            lock.lock()
            analysisInProgress = false
            lock.unlock()
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            ).perform([request])
        } catch {
            print("Video-page recognition failed: \(error.localizedDescription)")
            return
        }

        let observations = request.results ?? []
        let recognizedItems = observations.compactMap {
            observation -> (text: String, candidate: VNRecognizedText, box: CGRect)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (
                candidate.string.replacingOccurrences(of: " ", with: ""),
                candidate,
                observation.boundingBox
            )
        }
        let recognizedText = recognizedItems.map(\.text).joined(separator: " ")
        let compact = recognizedText.replacingOccurrences(of: " ", with: "")

        func containsToken(
            _ token: String,
            xRange: ClosedRange<CGFloat>,
            yRange: ClosedRange<CGFloat>
        ) -> Bool {
            recognizedItems.contains { item in
                guard let range = item.candidate.string.range(of: token) else { return false }
                let tokenBox = ((try? item.candidate.boundingBox(for: range))?.boundingBox)
                    ?? item.box
                return xRange.contains(tokenBox.midX) && yRange.contains(tokenBox.midY)
            }
        }

        // Vision uses normalized coordinates with the origin at bottom-left.
        // Require 首页 in the bottom-left navigation area and 推荐 in the upper
        // tab row. Merely finding those words somewhere in search results is
        // not enough to enable shortcuts.
        let hasBottomHomeTab = containsToken(
            "首页", xRange: 0.00...0.32, yRange: 0.00...0.18
        )
        let hasTopRecommendedTab = containsToken(
            "推荐", xRange: 0.52...1.00, yRange: 0.78...1.00
        )
        func englishBox(_ text: String, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> CGRect? {
            for item in recognizedItems {
                let pattern = text.components(separatedBy: " ")
                    .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "\\s*")
                guard let range = item.candidate.string.range(of: pattern, options: [.caseInsensitive, .regularExpression]) else { continue }
                // Word boundaries prevent "Send" from matching "Send to" below.
                let box = ((try? item.candidate.boundingBox(for: range))?.boundingBox) ?? item.box
                if x.contains(box.midX) && y.contains(box.midY) { return box }
            }
            return nil
        }
        let englishHome = englishBox("Home", x: 0...0.25, y: 0...0.15) != nil
        let englishForYou = englishBox("For You", x: 0.4...0.9, y: 0.78...0.97) != nil
        let isEnglishFeed = englishHome && englishForYou

        // The action rail moves vertically on videos that show extra cards or
        // recommendation rows. Its numeric counters are more stable OCR
        // targets than the icon shapes. The lowest counter on the right rail
        // belongs to Share; convert it to Quartz top-left coordinates and move
        // slightly upward to the center of the arrow icon.
        let rightRailCountBoxes = recognizedItems.compactMap { item -> CGRect? in
            let numeric = item.text.range(
                of: #"^[0-9０-９]+(?:[.．][0-9０-９]+)?(?:万|[wWkK])?$"#,
                options: .regularExpression
            ) != nil
            guard numeric,
                  item.box.midX >= 0.82,
                  (0.08...0.55).contains(item.box.midY) else { return nil }
            return item.box
        }
        let rightRailYPositions = rightRailCountBoxes.map(\.midY)
        let rightRailVerticalSpread = (rightRailYPositions.max() ?? 0)
            - (rightRailYPositions.min() ?? 0)
        // Bright captions or a busy video background can hide the selected
        // 推荐 / For You label from OCR. The bottom Home tab plus at least
        // three vertically separated numeric counters in the right action rail
        // is an equally strong feed signature. Search and chat may still show
        // a bottom tab bar, but they do not have this action rail.
        let hasVideoActionRail = rightRailCountBoxes.count >= 3
            && rightRailVerticalSpread >= 0.10
        let hasHomeTab = hasBottomHomeTab || englishHome
        let isHomeRecommendedFeed = (hasBottomHomeTab && hasTopRecommendedTab)
            || isEnglishFeed
            || (hasHomeTab && hasVideoActionRail)
        let inferredVideoSharePoint = rightRailCountBoxes.min {
            $0.midY < $1.midY
        }.map { box in
            CGPoint(
                x: config.shareButtonXRatio,
                y: min(0.88, max(0.55,
                    1 - box.midY - config.shareIconAboveCountRatio))
            )
        }
        let sendToBox = englishBox("Send to", x: 0.05...0.8, y: 0.2...0.65)
            ?? englishBox("Share to", x: 0.05...0.8, y: 0.2...0.65)
        let lowerEnglishActions = ["Copy link", "WhatsApp", "Repost", "Send", "Add message", "Write a message"]
            .filter { englishBox($0, x: 0...1, y: 0...0.5) != nil }.count
        let isEnglishShare = sendToBox != nil && lowerEnglishActions >= 1
        let sendBox = recognizedItems.first { item in
            let label = item.text.lowercased()
            return (label == "send" || label == "sendseparately") && item.box.midY < 0.35
        }?.box

        // Detect the share sheet independently so it also works when the user
        // opens it by clicking the UI rather than with Right Arrow. Evaluate it
        // before the feed because 推荐 can remain visible behind the sheet.
        let shareMarkers = [
            "最近分享", "转发到日常", "私信", "分享至群",
            "分别发送", "分享此刻的想法"
        ]
        let shareMarkerHits = shareMarkers.filter { compact.contains($0) }.count
        // After a recipient is selected, Douyin sometimes removes the lower
        // action row. In that state the stable markers are only 分享给 and the
        // red 发送 button, so recognize that compact layout too.
        let isShareSheet = isEnglishShare || (compact.contains("分享给")
            && (shareMarkerHits >= 1 || compact.contains("发送")))

        let detected: MirroredPageKind
        if isShareSheet {
            detected = .share
        } else if isHomeRecommendedFeed {
            detected = .video
        } else {
            detected = .other
        }

        lock.lock()
        guard contextRevision == analysisRevision else {
            lock.unlock()
            print("Discarded stale mirrored-page recognition result.")
            return
        }
        let changed = detected != pageKind
        pageKind = detected
        if detected == .video || detected == .share {
            englishTikTok = isEnglishFeed || isEnglishShare
        }
        // Convert Vision bottom-left coordinates to normalized Quartz top-left.
        englishShareHeader = isEnglishShare ? sendToBox.map { CGPoint(x: $0.midX, y: 1 - $0.midY) } : nil
        englishSendPoint = isEnglishShare ? sendBox.map { CGPoint(x: $0.midX, y: 1 - $0.midY) } : nil
        multipleShareSendButtonVisible = isShareSheet && compact.contains("分别发送")
        if detected == .video {
            lastConfirmedVideoUptime = ProcessInfo.processInfo.systemUptime
            lastConfirmedShareUptime = 0
            if let inferredVideoSharePoint {
                videoShareButtonPoint = inferredVideoSharePoint
                videoShareButtonPointUptime = ProcessInfo.processInfo.systemUptime
            }
        } else if detected == .share {
            lastConfirmedVideoUptime = 0
            lastConfirmedShareUptime = ProcessInfo.processInfo.systemUptime
        }
        lock.unlock()
        if changed {
            print("Detected mirrored page: \(detected.rawValue); OCR = \(recognizedText.prefix(180))")
        }
    }
}

// MARK: - Live floating preview (reliable always-on-top implementation)

final class FloatingPreviewActivationView: NSView {
    var activateMirroring: (() -> Void)?
    private let cornerMask = CAShapeLayer()
    private var topCornerRadius: CGFloat = 0
    private var bottomCornerRadius: CGFloat = 0

    func configureCornerMask(top: CGFloat, bottom: CGFloat) {
        wantsLayer = true
        topCornerRadius = max(0, top)
        bottomCornerRadius = max(0, bottom)
        layer?.mask = cornerMask
        updateCornerMask()
    }

    override func layout() {
        super.layout()
        updateCornerMask()
    }

    private func updateCornerMask() {
        let rect = bounds
        guard rect.width > 0, rect.height > 0 else { return }
        let top = min(topCornerRadius, min(rect.width, rect.height) / 2)
        let bottom = min(bottomCornerRadius, min(rect.width, rect.height) / 2)
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX + bottom, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + bottom),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - top),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottom, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()

        cornerMask.frame = rect
        cornerMask.path = path
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        activateMirroring?()
    }
}

final class FloatingPreviewController: NSObject, SCStreamOutput, SCStreamDelegate {
    private let config: Config
    private let mirroringController: IPhoneMirroringController
    private let pageContextDetector: PageContextDetector
    private let captureQueue = DispatchQueue(label: "iphone-scroll-control.capture")
    private let captureStateLock = NSLock()
    private var stream: SCStream?
    private var captureDesired = false
    private var captureStartInProgress = false
    private var panel: NSPanel?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var sourceWindowID: CGWindowID?
    private var frameTimer: Timer?
    private var suspendObserver: NSObjectProtocol?
    private var hideObserver: NSObjectProtocol?

    init(
        config: Config,
        mirroringController: IPhoneMirroringController,
        pageContextDetector: PageContextDetector
    ) {
        self.config = config
        self.mirroringController = mirroringController
        self.pageContextDetector = pageContextDetector
        super.init()
    }

    func start() {
        guard config.enableFloatingLivePreview else { return }

        suspendObserver = NotificationCenter.default.addObserver(
            forName: .iPhoneScrollControlWillSuspendTarget,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendPreviewAndCapture(reason: "window action")
        }
        hideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  self.config.allowedBundleIdentifiers.contains(app.bundleIdentifier ?? "")
                    || self.config.allowedApplicationNames.contains(app.localizedName ?? "")
            else { return }
            self.suspendPreviewAndCapture(reason: "application hidden")
        }

        guard CGPreflightScreenCaptureAccess() else {
            print("Screen Recording permission required for the floating live preview.")
            _ = CGRequestScreenCaptureAccess()
            return
        }

        Task { @MainActor [weak self] in
            self?.startFrameSyncTimer()
        }
        requestCaptureStart()
    }

    func stop() {
        frameTimer?.invalidate()
        frameTimer = nil
        panel?.orderOut(nil)
        panel = nil
        displayLayer = nil
        let activeStream = updateCaptureState(desired: false, takeActiveStream: true)
        if let activeStream {
            Task { try? await activeStream.stopCapture() }
        }
        if let suspendObserver {
            NotificationCenter.default.removeObserver(suspendObserver)
            self.suspendObserver = nil
        }
        if let hideObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(hideObserver)
            self.hideObserver = nil
        }
    }

    @MainActor
    private func suspendPreviewAndCapture(reason: String) {
        let wasVisible = panel?.isVisible == true
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        let activeStream = updateCaptureState(desired: false, takeActiveStream: true)
        guard wasVisible || activeStream != nil else { return }

        print("Floating preview and screen sharing suspended: \(reason).")
        if let activeStream {
            Task {
                do {
                    try await activeStream.stopCapture()
                    print("Screen capture stopped; sharing indicator can close.")
                } catch {
                    print("Failed to stop screen capture: \(error.localizedDescription)")
                }
            }
        }
    }

    private func requestCaptureStart() {
        captureStateLock.lock()
        captureDesired = true
        guard stream == nil, !captureStartInProgress else {
            captureStateLock.unlock()
            return
        }
        captureStartInProgress = true
        captureStateLock.unlock()

        Task { [weak self] in
            guard let self else { return }
            defer { finishCaptureStart() }

            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                guard let target = content.windows.first(where: {
                    $0.owningApplication?.bundleIdentifier == "com.apple.ScreenContinuity"
                        && $0.frame.width > 200
                        && $0.frame.height > 300
                }) else {
                    print("Floating preview: visible iPhone Mirroring window was not found.")
                    return
                }
                try await configureCapture(for: target)
            } catch {
                print("Floating preview failed: \(error.localizedDescription)")
            }
        }
    }

    private func finishCaptureStart() {
        captureStateLock.lock()
        captureStartInProgress = false
        captureStateLock.unlock()
    }

    private func updateCaptureState(
        desired: Bool,
        takeActiveStream: Bool = false
    ) -> SCStream? {
        captureStateLock.lock()
        defer { captureStateLock.unlock() }
        captureDesired = desired
        guard takeActiveStream else { return stream }
        let activeStream = stream
        stream = nil
        return activeStream
    }

    private func captureShouldRun() -> Bool {
        captureStateLock.lock()
        defer { captureStateLock.unlock() }
        return captureDesired
    }

    private func installStartedStream(_ newStream: SCStream) -> Bool {
        captureStateLock.lock()
        defer { captureStateLock.unlock() }
        guard captureDesired else { return false }
        stream = newStream
        return true
    }

    private func configureCapture(for target: SCWindow) async throws {
        let configuration = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        configuration.width = max(1, Int(target.frame.width * scale))
        configuration.height = max(1, Int(target.frame.height * scale))
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(max(1, config.floatingPreviewFPS))
        )
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: target)
        let newStream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try newStream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: captureQueue
        )

        guard captureShouldRun() else { return }
        try await newStream.startCapture()

        guard installStartedStream(newStream) else {
            try? await newStream.stopCapture()
            return
        }

        await MainActor.run {
            self.sourceWindowID = target.windowID
            if self.panel == nil {
                self.createPanel(frame: target.frame)
            } else {
                self.panel?.setFrame(
                    self.convertQuartzFrameToAppKit(target.frame),
                    display: true
                )
                if let panel = self.panel { self.updateMouseHandling(for: panel) }
            }
            if self.frameTimer == nil {
                self.startFrameSyncTimer()
            }
        }
        print("Floating live preview started for iPhone Mirroring window \(target.windowID).")
    }

    @MainActor
    private func createPanel(frame: CGRect) {
        let appKitFrame = convertQuartzFrameToAppKit(frame)
        let panel = NSPanel(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        // The captured iPhone frame already provides its own visual edge. An
        // NSPanel shadow shows through the transparent rounded corners as a
        // black crescent, so keep the floating panel itself shadow-free.
        panel.hasShadow = false
        panel.backgroundColor = .clear

        let view = FloatingPreviewActivationView(
            frame: CGRect(origin: .zero, size: appKitFrame.size)
        )
        view.activateMirroring = { [weak self] in
            self?.activateIPhoneMirroring()
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.configureCornerMask(
            top: config.floatingPreviewTopCornerRadius,
            bottom: config.floatingPreviewBottomCornerRadius
        )
        let layer = AVSampleBufferDisplayLayer()
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.videoGravity = .resizeAspect
        view.layer?.addSublayer(layer)
        panel.contentView = view
        updateMouseHandling(for: panel)

        self.panel = panel
        displayLayer = layer
        print("Floating preview panel placed at \(NSStringFromRect(appKitFrame)).")
    }

    @MainActor
    private func startFrameSyncTimer() {
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            guard let sourceWindowID else {
                if mirroringController.isTargetWindowInteractive() {
                    requestCaptureStart()
                }
                return
            }

            // A desktop-independent ScreenCaptureKit stream can keep producing
            // the last frame after its source window is hidden or minimized.
            // Do not let our floating preview make that window appear impossible
            // to hide: mirror the real window's on-screen state.
            guard isSourceWindowOnScreen(sourceWindowID) else {
                suspendPreviewAndCapture(reason: "source window is not on screen")
                // A relaunched iPhone Mirroring app can have a different window
                // ID. If it has a visible interactive window, rediscover it.
                if mirroringController.isTargetWindowInteractive() {
                    requestCaptureStart()
                }
                return
            }

            requestCaptureStart()

            guard let frame = quartzFrame(for: sourceWindowID) else { return }
            let appKitFrame = convertQuartzFrameToAppKit(frame)
            if panel?.frame != appKitFrame { panel?.setFrame(appKitFrame, display: true) }
            if let panel {
                updateMouseHandling(for: panel)
            }
        }
    }

    private func isSourceWindowOnScreen(_ windowID: CGWindowID) -> Bool {
        guard let app = mirroringController.runningTargetApplication(),
              !app.isHidden,
              let list = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return false
        }

        return list.contains { info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber else {
                return false
            }
            return CGWindowID(number.uint32Value) == windowID
        }
    }

    @MainActor
    private func updateMouseHandling(for panel: NSPanel) {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // The real window needs no duplicate window above it. Removing the
        // overlay also avoids racing WindowServer hit-testing during a gesture.
        let targetIsFrontmost = config.allowedBundleIdentifiers.contains(
            frontmostBundleID ?? ""
        )
        panel.ignoresMouseEvents = targetIsFrontmost
        if targetIsFrontmost {
            if panel.isVisible { panel.orderOut(nil) }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    @MainActor
    private func activateIPhoneMirroring() {
        guard let sourceWindowID, isSourceWindowOnScreen(sourceWindowID),
              mirroringController.isTargetWindowInteractive() else {
            suspendPreviewAndCapture(reason: "ignored click on suspended source")
            return
        }
        let activated = mirroringController.activateTargetApplication()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        print("Floating preview click: activated iPhone Mirroring = \(activated).")
    }

    private func quartzFrame(for windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[String: Any]],
        let info = list.first,
        let bounds = info[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    @MainActor
    private func convertQuartzFrameToAppKit(_ frame: CGRect) -> CGRect {
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: frame.minX,
            y: mainTop - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        pageContextDetector.inspect(sampleBuffer)
        displayLayer?.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Floating preview stream stopped: \(error.localizedDescription)")
    }
}

// MARK: - Gesture generation

// Captures both scroll-wheel events and their native scroll-gesture companions.
// No keyboard events, screen images, or other gesture subtypes are retained.
// Type 29/subtype 6 is an undocumented macOS event representation, isolated
// here; OS changes require fresh calibration. Do not synthesize its opaque
// payload or infer an opposite direction by negating its public delta fields.
final class NativeScrollCalibration {
    final class RuntimeSample: @unchecked Sendable {
        let offset: TimeInterval
        let event: CGEvent

        init(offset: TimeInterval, event: CGEvent) {
            self.offset = offset
            self.event = event
        }
    }
    struct Sample: Codable {
        let offset: TimeInterval
        let data: Data
    }
    struct Archive: Codable {
        var version = 4
        let system: String
        let next: [Sample]
        let previous: [Sample]
    }
    static let shared = NativeScrollCalibration()
    private let lock = NSLock()
    private let saveQueue = DispatchQueue(label: "iphone-scroll-control.calibration-save")
    private var profiles: [String: [RuntimeSample]] = [:]
    private var serializedProfiles: [String: [Sample]] = [:]
    // Pending data is accessed only on the event-tap main run loop.
    private var pending: [Sample] = []
    private var pendingNative: [RuntimeSample] = []
    private var started: TimeInterval = 0
    private var lastEventUptime: TimeInterval = 0
    private var captureGeneration: UInt64 = 0
    private var total: Int64 = 0
    private let fileURL: URL
    static let companionEventType: UInt32 = 29
    private static let companionSubtype = CGEventField(rawValue: 110)!
    private static let companionPhase = CGEventField(rawValue: 132)!

    static func isSupportedEvent(_ event: CGEvent) -> Bool {
        if event.type == .scrollWheel {
            return event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        }
        return event.type.rawValue == companionEventType
            && event.getIntegerValueField(companionSubtype) == 6
    }

    fileprivate init(fileURL: URL? = nil) {
        // CGEvent's public serialized representation round-trips all fields we
        // can inspect, but TikTok in iPhone Mirroring does not commit paging
        // when those re-created events are posted. The original in-memory
        // CGEvent copies do work in both directions. Production therefore
        // records a fresh pair for each process lifetime. Tests inject a URL
        // and still exercise archive validation without enabling the broken
        // production restore path.
        let loadPersistedEvents = fileURL != nil
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iPhoneScrollControl/TikTokNativeGestures-v4.json")
        let fileURL = self.fileURL
        guard loadPersistedEvents else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                print("Stored TikTok gesture metadata found; fresh in-memory calibration is required after every tool restart.")
            }
            return
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 8_388_608,
              let bytes = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: bytes),
              archive.version == 4,
              archive.system == ProcessInfo.processInfo.operatingSystemVersionString else { return }
        for (key, samples) in [("up", archive.next), ("down", archive.previous)] {
            guard Self.valid(samples) else { continue }
            let native = samples.compactMap { sample -> RuntimeSample? in
                guard let event = CGEvent(withDataAllocator: nil, data: sample.data as CFData) else { return nil }
                return RuntimeSample(offset: sample.offset, event: event)
            }
            let total = native.filter { $0.event.type == .scrollWheel }
                .reduce(Int64(0)) { $0 + $1.event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
            let directionMatches = key == "up" ? total <= -40 : total >= 40
            guard Self.isComplete(native), directionMatches else { continue }
            profiles[key] = native
            serializedProfiles[key] = samples
            print("Loaded TikTok \(key == "up" ? "NEXT" : "PREVIOUS") native gesture: \(native.count) events (wheel + companions).")
        }
    }

    private static func valid(_ samples: [Sample]) -> Bool {
        guard (5...800).contains(samples.count), let last = samples.last, last.offset <= 3 else { return false }
        var previous: TimeInterval = 0
        for sample in samples {
            guard sample.offset.isFinite, sample.offset >= previous, sample.data.count < 65_536,
                  let event = CGEvent(withDataAllocator: nil, data: sample.data as CFData),
                  Self.isSupportedEvent(event) else { return false }
            let deltaFields: [CGEventField] = event.type == .scrollWheel
                ? [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
                : [CGEventField(rawValue: 116)!, CGEventField(rawValue: 119)!]
            guard deltaFields.allSatisfy({ field in
                let value = event.getDoubleValueField(field)
                return value.isFinite && abs(value) <= 1_000_000
            }) else { return false }
            previous = sample.offset
        }
        return true
    }

    func profile(_ direction: SwipeDirection) -> [RuntimeSample]? {
        lock.lock(); defer { lock.unlock() }
        return profiles[direction.rawValue]
    }

    private static func isComplete(_ samples: [RuntimeSample]) -> Bool {
        guard samples.allSatisfy({ isSupportedEvent($0.event) }),
              samples.filter({ $0.event.type.rawValue == companionEventType }).count >= 2 else { return false }
        var companionStarted = false, companionEnded = false
        for sample in samples where sample.event.type.rawValue == companionEventType {
            switch sample.event.getIntegerValueField(companionPhase) {
            case 128: guard !companionStarted else { return false }
            case 1: guard !companionStarted else { return false }; companionStarted = true
            case 2: guard companionStarted && !companionEnded else { return false }
            case 4: guard companionStarted && !companionEnded else { return false }; companionEnded = true
            case 0: break
            default: return false
            }
        }
        guard companionStarted && companionEnded else { return false }
        let scrolls = samples.filter { $0.event.type == .scrollWheel }
        guard scrolls.count >= 3 else { return false }
        var fingerStarted = false, fingerEnded = false
        var momentumStarted = false, momentumEnded = false
        for sample in scrolls {
            let phase = sample.event.getIntegerValueField(.scrollWheelEventScrollPhase)
            let momentum = sample.event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            guard phase != 8, !momentumEnded else { return false }
            switch phase {
            case 128: guard !fingerStarted else { return false }
            case 1: guard !fingerStarted else { return false }; fingerStarted = true
            case 2: guard fingerStarted && !fingerEnded else { return false }
            case 4: guard fingerStarted && !fingerEnded else { return false }; fingerEnded = true
            case 0: break
            default: return false
            }
            switch momentum {
            case 1: guard fingerEnded && !momentumStarted else { return false }; momentumStarted = true
            case 2: guard momentumStarted else { return false }
            case 3: guard momentumStarted else { return false }; momentumEnded = true
            case 0: break
            default: return false
            }
        }
        return fingerStarted && fingerEnded && (!momentumStarted || momentumEnded)
    }

    func cancelCapture() {
        captureGeneration &+= 1
        started = 0
        pending.removeAll()
        pendingNative.removeAll()
    }

    func observe(_ event: CGEvent, mayStart: Bool) {
        guard Self.isSupportedEvent(event) else { return }
        let phase = event.getIntegerValueField(event.type == .scrollWheel
            ? .scrollWheelEventScrollPhase : Self.companionPhase)
        let now = ProcessInfo.processInfo.systemUptime

        // Vision can briefly classify the animated feed as `other` while it
        // moves. Use page recognition only to admit the first event, then keep
        // every native event through the end of momentum. Previously the
        // caller filtered every event through OCR, which silently dropped the
        // gesture tail and prevented a calibration file from ever being made.
        let beginsGesture = phase == 128 || phase == 1
            || (started == 0 && now - lastEventUptime > 0.6)
        if started == 0, beginsGesture, mayStart {
            pending.removeAll()
            pendingNative.removeAll()
            total = 0
            started = now
            print("TikTok native gesture capture started (wheel + companion events).")
        }
        lastEventUptime = now
        guard started > 0 else { return }
        guard now - started < 3, pending.count < 800 else {
            print("TikTok calibration discarded: gesture exceeded capture limits.")
            started = 0
            pending.removeAll()
            pendingNative.removeAll()
            return
        }
        guard let nativeCopy = event.copy(), let bytes = event.data else { return }
        pendingNative.append(RuntimeSample(offset: now - started, event: nativeCopy))
        pending.append(Sample(offset: now - started, data: bytes as Data))
        if event.type == .scrollWheel { total += event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }

        // Wait for both streams to become quiet: a companion can arrive after
        // the last wheel event. Stopping at wheel momentum-ended alone can
        // truncate its native gesture data.
        captureGeneration &+= 1
        let generation = captureGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.captureGeneration == generation,
                  self.started > 0 else { return }
            self.finishCapture()
        }
    }

    private func finishCapture() {
        defer { started = 0; pending.removeAll(); pendingNative.removeAll() }
        guard abs(total) >= 40, pendingNative.count == pending.count,
              Self.valid(pending), Self.isComplete(pendingNative) else {
            print("TikTok calibration discarded: incomplete gesture (events=\(pending.count), total=\(total)).")
            return
        }
        let key = total < 0 ? "up" : "down"
        lock.lock()
        // Do not overwrite a calibration with subsequent incidental scrolling.
        guard profiles[key] == nil else { lock.unlock(); return }
        profiles[key] = pendingNative
        serializedProfiles[key] = pending
        let archive = Archive(system: ProcessInfo.processInfo.operatingSystemVersionString,
                              next: serializedProfiles["up"] ?? [],
                              previous: serializedProfiles["down"] ?? [])
        lock.unlock()
        let wheelCount = pendingNative.filter { $0.event.type == .scrollWheel }.count
        print("Calibrated TikTok \(total < 0 ? "NEXT" : "PREVIOUS"): wheel=\(wheelCount), companions=\(pending.count - wheelCount), total=\(total)")
        let url = fileURL
        saveQueue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(archive).write(to: url, options: .atomic)
                print("Saved local native scroll calibration: \(url.path)")
            } catch { print("Could not save calibration: \(error.localizedDescription)") }
        }
    }
}

final class SwipeController {
    private let config: Config
    private let mirroringController: IPhoneMirroringController
    private let pageContextDetector: PageContextDetector
    private let gestureQueue = DispatchQueue(label: "iphone-scroll-control.gestures")
    private let swipeLock = NSLock()
    private var swipeInFlight = false

    init(config: Config, mirroringController: IPhoneMirroringController, pageContextDetector: PageContextDetector) {
        self.config = config
        self.mirroringController = mirroringController
        self.pageContextDetector = pageContextDetector
    }

    func performSwipe(
        _ direction: SwipeDirection,
        app: NSRunningApplication,
        ensureContentFocus: Bool = false
    ) {
        swipeLock.lock()
        guard !swipeInFlight else {
            swipeLock.unlock()
            print("Swipe ignored: one gesture is already in progress (no queue).")
            return
        }
        swipeInFlight = true
        swipeLock.unlock()
        gestureQueue.async { [self] in
            defer {
                swipeLock.lock(); swipeInFlight = false; swipeLock.unlock()
            }
            mirroringController.waitForActivationToSettle()
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  !app.isHidden,
                  let frame = mirroringController.focusedWindowFrame(of: app) else { return }

            if ensureContentFocus && !pageContextDetector.tikTokLayout().enabled {
                let focusPoint = CGPoint(x: frame.midX, y: frame.midY)
                print("Focusing mirrored content before first swipe at \(pointDescription(focusPoint)).")
                // This click is generated by the tool. Mark it so the global
                // event tap does not count it as a user playback toggle.
                postMouse(
                    type: .leftMouseDown,
                    point: focusPoint,
                    button: .left,
                    replayMarker: syntheticReplayMarker
                )
                usleep(40_000)
                postMouse(
                    type: .leftMouseUp,
                    point: focusPoint,
                    button: .left,
                    replayMarker: syntheticReplayMarker
                )
                usleep(120_000)
            }

            if config.useScrollWheelFallback {
                performScroll(direction, in: frame)
            } else {
                performDrag(direction, in: frame)
            }
        }
    }

    func performCenterClick(app: NSRunningApplication) {
        gestureQueue.async { [self] in
            mirroringController.waitForActivationToSettle()
            guard let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let point = CGPoint(
                x: frame.minX + frame.width * config.middleClickXRatio,
                y: frame.minY + frame.height * config.middleClickYRatio
            )
            print("Performing center click:\n  window = \(frameDescription(frame))\n  point = \(pointDescription(point))")
            postMouse(
                type: .leftMouseDown,
                point: point,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
            usleep(40_000)
            postMouse(
                type: .leftMouseUp,
                point: point,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
        }
    }

    func performSystemShortcut(keyCode: Int64) {
        gestureQueue.async { [self] in
            print("Performing Command shortcut without playback click, keyCode = \(keyCode).")
            postCommandShortcut(keyCode: keyCode)
        }
    }

    func performWindowButtonClick(at buttonPoint: CGPoint) {
        gestureQueue.async { [self] in
            print("Clicking window button without playback click.")
            postMouse(
                type: .leftMouseDown,
                point: buttonPoint,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
            usleep(40_000)
            postMouse(
                type: .leftMouseUp,
                point: buttonPoint,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
        }
    }

    func pauseThenPerformSystemShortcut(
        keyCode: Int64,
        app: NSRunningApplication
    ) {
        gestureQueue.async { [self] in
            guard let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let point = CGPoint(x: frame.midX, y: frame.midY)
            print("Pausing video before Command shortcut, keyCode = \(keyCode).")
            postMouse(
                type: .leftMouseDown,
                point: point,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
            usleep(40_000)
            postMouse(
                type: .leftMouseUp,
                point: point,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
            usleep(useconds_t(config.pauseBeforeWindowActionDelay * 1_000_000))
            postCommandShortcut(keyCode: keyCode)
        }
    }

    func pauseThenPerformWindowButtonClick(
        at buttonPoint: CGPoint,
        app: NSRunningApplication
    ) {
        gestureQueue.async { [self] in
            guard let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let pausePoint = CGPoint(x: frame.midX, y: frame.midY)
            print("Pausing video before minimizing the window.")
            postMouse(
                type: .leftMouseDown,
                point: pausePoint,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
            usleep(40_000)
            postMouse(
                type: .leftMouseUp,
                point: pausePoint,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
            usleep(useconds_t(config.pauseBeforeWindowActionDelay * 1_000_000))
            postMouse(
                type: .leftMouseDown,
                point: buttonPoint,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
            usleep(40_000)
            postMouse(
                type: .leftMouseUp,
                point: buttonPoint,
                button: .left,
                replayMarker: syntheticReplayMarker
            )
        }
    }

    func performFocusClick(at point: CGPoint) {
        gestureQueue.async { [self] in
            mirroringController.waitForActivationToSettle()
            print("Relaying activation click to iPhone Mirroring at \(pointDescription(point)).")
            postMouse(type: .leftMouseDown, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
            usleep(40_000)
            postMouse(type: .leftMouseUp, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
        }
    }

    func performLike(app: NSRunningApplication) {
        gestureQueue.async { [self] in
            mirroringController.waitForActivationToSettle()
            guard let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let point = CGPoint(x: frame.midX, y: frame.midY)
            print("Performing double-click like at \(pointDescription(point)).")
            postMouse(type: .leftMouseDown, point: point, button: .left,
                      clickState: 1, replayMarker: syntheticReplayMarker)
            postMouse(type: .leftMouseUp, point: point, button: .left,
                      clickState: 1, replayMarker: syntheticReplayMarker)
            usleep(90_000)
            postMouse(type: .leftMouseDown, point: point, button: .left,
                      clickState: 2, replayMarker: syntheticReplayMarker)
            postMouse(type: .leftMouseUp, point: point, button: .left,
                      clickState: 2, replayMarker: syntheticReplayMarker)
        }
    }

    func openShareSheet(app: NSRunningApplication) {
        gestureQueue.async { [self] in
            guard let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let detectedPoint = pageContextDetector.detectedVideoShareButtonPoint()
            let point = CGPoint(
                x: frame.minX + frame.width * (detectedPoint?.x
                    ?? config.shareButtonXRatio),
                y: frame.minY + frame.height * (detectedPoint?.y
                    ?? (pageContextDetector.tikTokLayout().enabled
                        ? config.tikTokShareButtonYRatio : config.shareButtonYRatio))
            )
            print("Opening share sheet at \(pointDescription(point)) "
                + "[\(detectedPoint == nil ? "fallback" : "detected action rail")].")
            postMouse(type: .leftMouseDown, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
            usleep(40_000)
            postMouse(type: .leftMouseUp, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
        }
    }

    func closeShareSheet(app: NSRunningApplication) {
        gestureQueue.async { [self] in
            guard let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let layout = pageContextDetector.tikTokLayout()
            if layout.enabled && layout.header == nil { return }
            let point = CGPoint(
                x: frame.minX + frame.width * config.shareCloseXRatio,
                y: frame.minY + frame.height * (layout.enabled ? layout.header!.y : config.shareCloseYRatio)
            )
            print("Closing share sheet at \(pointDescription(point)).")
            postMouse(type: .leftMouseDown, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
            usleep(40_000)
            postMouse(type: .leftMouseUp, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
        }
    }

    func selectShareRecipient(_ index: Int, app: NSRunningApplication) {
        gestureQueue.async { [self] in
            let layout = pageContextDetector.tikTokLayout()
            if layout.enabled && layout.header == nil { return }
            guard config.shareRecipientXRatios.indices.contains(index),
                  let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let point = CGPoint(
                x: frame.minX + frame.width * (layout.enabled ? config.tikTokRecipientXRatios[index] : config.shareRecipientXRatios[index]),
                y: frame.minY + frame.height * (layout.enabled ? layout.header!.y + 0.055 : config.shareRecipientYRatio)
            )
            print("Selecting share recipient \(index + 1) at \(pointDescription(point)).")
            postMouse(type: .leftMouseDown, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
            usleep(40_000)
            postMouse(type: .leftMouseUp, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
        }
    }

    func sendSharedVideo(selectionCount: Int, app: NSRunningApplication) {
        gestureQueue.async { [self] in
            let layout = pageContextDetector.tikTokLayout()
            if layout.enabled && layout.send == nil {
                print("TikTok Send button not recognized; skipping click.")
                return
            }
            guard selectionCount > 0,
                  let frame = mirroringController.focusedWindowFrame(of: app) else { return }
            let xRatio = selectionCount == 1
                ? config.shareSendSingleXRatio
                : config.shareSendMultipleXRatio
            let point = CGPoint(
                x: frame.minX + frame.width * (layout.enabled ? layout.send!.x : xRatio),
                y: frame.minY + frame.height * (layout.enabled ? layout.send!.y : config.shareSendYRatio)
            )
            print("Sending shared video to \(selectionCount) recipient(s) at \(pointDescription(point)).")
            postMouse(type: .leftMouseDown, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
            usleep(40_000)
            postMouse(type: .leftMouseUp, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
        }
    }

    private func performDrag(_ direction: SwipeDirection, in frame: CGRect) {
        let upStart = config.swipeStartRatio
        let upEnd = config.swipeEndRatio
        let startRatio = direction == .up ? upStart : upEnd
        let endRatio = direction == .up ? upEnd : upStart
        let start = CGPoint(
            x: frame.minX + frame.width * config.horizontalRatio,
            y: frame.minY + frame.height * startRatio
        )
        let end = CGPoint(
            x: frame.minX + frame.width * config.horizontalRatio,
            y: frame.minY + frame.height * endRatio
        )
        let steps = max(2, config.swipeSteps)
        let stepDelay = max(0, config.swipeDuration) / Double(steps)

        print("Performing swipe:\n  direction = \(direction.rawValue)\n  window = \(frameDescription(frame))\n  start = \(pointDescription(start))\n  end = \(pointDescription(end))")

        postMouse(type: .leftMouseDown, point: start, button: .left,
                  replayMarker: syntheticReplayMarker)
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            // Smoothstep avoids an unnaturally constant drag velocity.
            let eased = progress * progress * (3 - 2 * progress)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * eased,
                y: start.y + (end.y - start.y) * eased
            )
            postMouse(type: .leftMouseDragged, point: point, button: .left,
                      replayMarker: syntheticReplayMarker)
            if stepDelay > 0 {
                usleep(useconds_t(stepDelay * 1_000_000))
            }
        }
        postMouse(type: .leftMouseUp, point: end, button: .left,
                  replayMarker: syntheticReplayMarker)
    }

    private func performScroll(_ direction: SwipeDirection, in frame: CGRect) {
        if pageContextDetector.tikTokLayout().enabled {
            performTikTokScroll(direction, in: frame)
            return
        }
        let point = CGPoint(
            x: frame.minX + frame.width * config.horizontalRatio,
            y: frame.midY
        )
        // A finger swipe up means scrolling down to the next item, which is a
        // negative vertical wheel delta. Previous is the opposite direction.
        let sign: Int32 = direction == .up ? -1 : 1
        let delta = sign * abs(config.scrollLineDelta) * config.scrollDirectionMultiplier
        let count = max(1, config.scrollBurstCount)
        let stepDelay = max(0, config.scrollBurstDuration) / Double(count)
        print("Performing scroll fallback:\n  direction = \(direction.rawValue)\n  window = \(frameDescription(frame))\n  point = \(pointDescription(point))\n  line delta per event = \(delta)\n  event count = \(count)")

        CGWarpMouseCursorPosition(point)
        usleep(15_000)

        // A plain line event produced a visible response in iPhone Mirroring.
        // Emit a short burst, like a decisive physical mouse-wheel flick, to
        // cross Douyin's paging threshold.
        for _ in 0..<count {
            postLineScroll(delta: delta, at: point)
            if stepDelay > 0 {
                usleep(useconds_t(stepDelay * 1_000_000))
            }
        }
    }

    private func postLineScroll(delta: Int32, at point: CGPoint) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else {
            print("Failed to create scroll-wheel event.")
            return
        }
        event.location = point
        event.setIntegerValueField(.eventSourceUserData, value: syntheticReplayMarker)
        event.post(tap: .cghidEventTap)
    }

    private func performTikTokScroll(_ direction: SwipeDirection, in frame: CGRect) {
        guard let samples = NativeScrollCalibration.shared.profile(direction) else {
            print("TikTok calibration required: use the trackpad once to \(direction == .up ? "go to NEXT" : "go to PREVIOUS") video, then retry the key.")
            return
        }
        guard let target = mirroringController.frontmostTargetApplication(),
              let pointer = CGEvent(source: nil)?.location else { return }
        let content = frame.insetBy(dx: frame.width * 0.15, dy: frame.height * 0.18)
        let point = content.contains(pointer) ? pointer
            : CGPoint(x: frame.minX + frame.width * config.horizontalRatio, y: frame.midY)
        // Arrows also work after Command-Tab with the pointer outside the phone.
        // Move once, never in a loop. Any subsequent real movement cancels this
        // bounded gesture, so the user can always leave the mirrored window.
        if point != pointer {
            CGWarpMouseCursorPosition(point)
            usleep(20_000)
        }
        let start = ProcessInfo.processInfo.systemUptime
        var sent = 0
        print("Replaying calibrated TikTok \(direction == .up ? "NEXT" : "PREVIOUS"): \(samples.count) events, duration=\(samples.last?.offset ?? 0)s")
        for sample in samples {
            // Absolute deadlines prevent callback/WindowServer overhead from
            // stretching the gesture on every sample (measured +24% before).
            let delay = start + sample.offset - ProcessInfo.processInfo.systemUptime
            if delay > 0 { usleep(useconds_t(delay * 1_000_000)) }
            let currentPointer = CGEvent(source: nil)?.location ?? point
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  !target.isHidden,
                  hypot(currentPointer.x - point.x, currentPointer.y - point.y) < 24 else {
                // Terminate only the original target's gesture; do not inject
                // into a newly focused app or warp the pointer back to the phone.
                if sent > 0, let cancel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                    wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0) {
                    cancel.location = currentPointer
                    cancel.setIntegerValueField(.scrollWheelEventScrollPhase, value: 8)
                    cancel.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3)
                    cancel.setIntegerValueField(.eventSourceUserData, value: syntheticReplayMarker)
                    cancel.postToPid(target.processIdentifier)
                }
                print("TikTok replay cancelled after \(sent) events: focus/visibility/pointer changed.")
                return
            }
            guard let event = sample.event.copy(), NativeScrollCalibration.isSupportedEvent(event) else { return }
            event.location = point
            event.timestamp = DispatchTime.now().uptimeNanoseconds
            event.setIntegerValueField(.eventSourceUserData, value: syntheticReplayMarker)
            event.post(tap: .cgSessionEventTap)
            sent += 1
        }
        print(String(format: "TikTok replay completed: %d events in %.3fs.", sent,
                     ProcessInfo.processInfo.systemUptime - start))
    }

    // Retained for diagnostics only; the production TikTok path uses native
    // calibrated events because constructed events rebounded on this device.
    private func performUncalibratedTikTokScroll(_ direction: SwipeDirection, in frame: CGRect) {
        let point = CGPoint(x: frame.minX + frame.width * config.horizontalRatio, y: frame.midY)
        let sign: CGFloat = direction == .up ? -1 : 1
        // Runtime calibration avoids replacing the signed app for a distance
        // adjustment. Missing/invalid values use the tested default.
        let configuredRatio = UserDefaults.standard.double(forKey: "TikTokScrollHeightRatio")
        let ratio = configuredRatio.isFinite && configuredRatio >= 0.25 && configuredRatio <= 3
            ? CGFloat(configuredRatio) : config.tikTokScrollHeightRatio
        let total = Int32((sign * frame.height * ratio
            * CGFloat(config.scrollDirectionMultiplier)).rounded())
        let steps = max(2, config.swipeSteps)
        let delay = max(0.01, config.tikTokScrollDuration) / Double(steps)
        print("Performing TikTok continuous scroll: direction = \(direction.rawValue), pixels = \(total), steps = \(steps)")
        CGWarpMouseCursorPosition(point)
        usleep(20_000)
        func post(_ delta: Int32, phase: Int64, momentum: Int64 = 0) {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                      wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
            event.location = point
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            event.setIntegerValueField(.eventSourceUserData, value: syntheticReplayMarker)
            event.post(tap: .cghidEventTap)
        }
        // Match the observed trackpad lifecycle, including lift-off momentum.
        // Sending a zero-distance began followed by uniform deltas and no
        // momentum only made this TikTok version rebound to the same video.
        post(0, phase: Int64(CGScrollPhase.mayBegin.rawValue))
        usleep(8_000)
        let fingerTotal = Int32((Double(total) * 0.30).rounded())
        var sent: Int32 = 0
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let target = Int32((Double(fingerTotal) * progress * progress).rounded())
            post(target - sent, phase: Int64(step == 1 ? CGScrollPhase.began.rawValue : CGScrollPhase.changed.rawValue))
            sent = target
            usleep(useconds_t(delay * 1_000_000))
        }
        post(0, phase: Int64(CGScrollPhase.ended.rawValue))
        // Smooth deceleration with a bounded total distance; never append an
        // unbounded second scroll burst after the feed has already paged.
        let momentumTotal = total - fingerTotal
        let momentumSteps = 32
        sent = 0
        for step in 1...momentumSteps {
            let progress = Double(step) / Double(momentumSteps)
            let eased = 1 - pow(1 - progress, 3)
            let target = Int32((Double(momentumTotal) * eased).rounded())
            post(target - sent, phase: 0, momentum: step == 1 ? 1 : 2)
            sent = target
            usleep(8_000)
        }
        post(0, phase: 0, momentum: 3)
    }

    private func postMouse(
        type: CGEventType,
        point: CGPoint,
        button: CGMouseButton,
        clickState: Int64 = 1,
        replayMarker: Int64 = 0
    ) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            print("Failed to create mouse event: \(type.rawValue)")
            return
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        if replayMarker != 0 {
            event.setIntegerValueField(.eventSourceUserData, value: replayMarker)
        }
        event.post(tap: .cghidEventTap)
    }


    private func postCommandShortcut(keyCode: Int64) {
        guard let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        ),
        let up = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: false
        ) else {
            print("Failed to replay Command shortcut, keyCode = \(keyCode).")
            return
        }
        for event in [down, up] {
            event.flags = [.maskCommand]
            event.setIntegerValueField(.eventSourceUserData, value: syntheticReplayMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Global side-button event tap

final class MouseEventMonitor {
    private let config: Config
    private let mirroringController: IPhoneMirroringController
    private let swipeController: SwipeController
    private let pageContextDetector: PageContextDetector
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var nativeCaptureTap: CFMachPort?
    private var nativeCaptureRunLoopSource: CFRunLoopSource?
    private var lastTriggerByButton: [Int64: TimeInterval] = [:]
    private var consumeNextLeftMouseUp = false
    private var consumedKeyboardKeyUps: Set<Int64> = []
    private var lastKeyboardTriggerByKey: [Int64: TimeInterval] = [:]
    private var shareSelectionStartedUptime: TimeInterval?
    private var selectedShareRecipients: Set<Int> = []
    private var textInputProtectionUntil: TimeInterval = 0
    private var lastTikTokWheelUptime: TimeInterval = 0
    // Douyin normally starts a feed video automatically. Keep this state in
    // sync with Space, navigation, and direct taps so hide/minimize is
    // idempotent: it pauses only when playback is currently active.
    private var videoIsPlaying = true
    private var needsContentFocusBeforeSwipe = true
    private var workspaceActivationObserver: NSObjectProtocol?
    // AX can block long enough to interrupt the cadence of a trackpad gesture.
    // Refresh this on the main run loop, never once per scroll event in the tap.
    private struct ScrollTargetSnapshot {
        let app: NSRunningApplication
        let frame: CGRect
        let capturedUptime: TimeInterval
    }
    private var scrollTargetSnapshot: ScrollTargetSnapshot?
    private var scrollTargetRefreshTimer: Timer?

    init(
        config: Config,
        mirroringController: IPhoneMirroringController,
        swipeController: SwipeController,
        pageContextDetector: PageContextDetector
    ) {
        self.config = config
        self.mirroringController = mirroringController
        self.swipeController = swipeController
        self.pageContextDetector = pageContextDetector
    }

    func start() -> Bool {
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        // iPhone Mirroring can consume navigation keys before a session-level
        // tap observes them. Listen at HID level so arrows are seen before the
        // mirrored device handles them (Input Monitoring is still required).
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            print("Failed to create event tap.")
            print("Please enable Input Monitoring / Accessibility permissions, then restart the program.")
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else {
            print("Failed to create event-tap run-loop source.")
            stop()
            return false
        }

        // A real trackpad gesture includes companion gesture events which are
        // absent from a scrollWheel-only recording. Capture both at the session
        // tail without modifying input; HID still owns shortcut interception.
        let captureMask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
            | (CGEventMask(1) << NSEvent.EventType.gesture.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
        nativeCaptureTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: captureMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<MouseEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.observeNativeScroll(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let nativeCaptureTap else {
            print("Failed to create native scroll capture event tap.")
            print("Please enable Input Monitoring / Accessibility permissions, then restart the program.")
            stop()
            return false
        }
        nativeCaptureRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, nativeCaptureTap, 0
        )
        guard let nativeCaptureRunLoopSource else {
            print("Failed to create native scroll capture run-loop source.")
            stop()
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), nativeCaptureRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        CGEvent.tapEnable(tap: nativeCaptureTap, enable: true)
        refreshScrollTargetSnapshot()
        let refreshTimer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.refreshScrollTargetSnapshot()
        }
        scrollTargetRefreshTimer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            let bundleMatches = app.bundleIdentifier.map {
                self.config.allowedBundleIdentifiers.contains($0)
            } ?? false
            let nameMatches = app.localizedName.map {
                self.config.allowedApplicationNames.contains($0)
            } ?? false
            if bundleMatches || nameMatches {
                self.needsContentFocusBeforeSwipe = true
                self.refreshScrollTargetSnapshot()
                print("iPhone Mirroring activated; next swipe will restore content focus.")
            } else {
                self.clearScrollTargetSnapshot()
            }
        }
        print("Mouse monitor active. Press side buttons to display their button numbers.")
        print("Native scroll capture active: session tail, scroll + companion gesture events, listen-only.")
        return true
    }

    func stop() {
        scrollTargetRefreshTimer?.invalidate()
        scrollTargetRefreshTimer = nil
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
            self.workspaceActivationObserver = nil
        }
        for source in [runLoopSource, nativeCaptureRunLoopSource].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        for tap in [eventTap, nativeCaptureTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        nativeCaptureRunLoopSource = nil
        eventTap = nil
        nativeCaptureTap = nil
        clearScrollTargetSnapshot()
    }

    deinit {
        stop()
    }

    private func observeNativeScroll(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NativeScrollCalibration.shared.cancelCapture()
            if let nativeCaptureTap { CGEvent.tapEnable(tap: nativeCaptureTap, enable: true) }
            print("Native scroll capture tap was disabled and has been re-enabled; partial capture discarded.")
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != syntheticReplayMarker else {
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown {
            NativeScrollCalibration.shared.cancelCapture()
            return Unmanaged.passUnretained(event)
        }
        guard NativeScrollCalibration.isSupportedEvent(event) else {
            return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        // Companion gestures can carry a zero/non-screen event location.
        // Hit-test their current cursor location instead of dropping them.
        let capturePoint: CGPoint? = type == .scrollWheel
            ? event.location : CGEvent(source: nil)?.location
        guard let snapshot = scrollTargetSnapshot,
              let capturePoint,
              now - snapshot.capturedUptime <= 0.25,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.app.processIdentifier,
              !snapshot.app.isHidden,
              snapshot.frame.contains(capturePoint) else {
            NativeScrollCalibration.shared.cancelCapture()
            return Unmanaged.passUnretained(event)
        }
        NativeScrollCalibration.shared.observe(event,
            mayStart: pageContextDetector.tikTokLayout().enabled
                && pageContextDetector.isVideoPageOrRecentlyConfirmed()
                && now >= textInputProtectionUntil)
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            print("Event tap was disabled and has been re-enabled.")
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticReplayMarker {
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown {
            // A consumed HID click might never reach the listen-only session
            // tap, so discard a partial capture before any click routing.
            NativeScrollCalibration.shared.cancelCapture()
        }

        if type == .scrollWheel {
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
                return Unmanaged.passUnretained(event)
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard let snapshot = scrollTargetSnapshot,
                  now - snapshot.capturedUptime <= 0.25,
                  snapshot.frame.contains(event.location) else {
                NativeScrollCalibration.shared.cancelCapture()
                return Unmanaged.passUnretained(event)
            }

            // Only discrete mouse wheels on a confirmed TikTok feed are
            // converted. Every other scroll must pass through here, not enter
            // the side-button branch: mouseEventButtonNumber is not a scroll
            // event field and cannot be used to decide whether to consume it.
            guard config.tikTokWheelPaging,
                  event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
                  pageContextDetector.tikTokLayout().enabled,
                  pageContextDetector.currentPageKind() == .video,
                  now >= textInputProtectionUntil else {
                return Unmanaged.passUnretained(event)
            }
            let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            guard delta != 0,
                  event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0 else {
                return Unmanaged.passUnretained(event)
            }
            guard NativeScrollCalibration.shared.profile(delta < 0 ? .up : .down) != nil else {
                return Unmanaged.passUnretained(event)
            }
            let quiet = now - lastTikTokWheelUptime >= config.tikTokWheelQuietInterval
            lastTikTokWheelUptime = now
            if quiet {
                videoIsPlaying = true
                swipeController.performSwipe(delta < 0 ? .up : .down, app: snapshot.app)
            }
            return nil
        }

        if type == .leftMouseUp, consumeNextLeftMouseUp {
            consumeNextLeftMouseUp = false
            return nil
        }

        if type == .leftMouseDown,
           config.pauseBeforeMinimizeOrHide,
           let targetApp = mirroringController.frontmostTargetApplication(),
           pageContextDetector.isVideoPageOrRecentlyConfirmed(),
           let minimizeFrame = mirroringController.minimizeButtonFrame(of: targetApp),
           minimizeFrame.insetBy(dx: -5, dy: -5).contains(event.location) {
            NotificationCenter.default.post(
                name: .iPhoneScrollControlWillSuspendTarget,
                object: nil
            )
            consumeNextLeftMouseUp = true
            if videoIsPlaying {
                videoIsPlaying = false
                swipeController.pauseThenPerformWindowButtonClick(
                    at: event.location,
                    app: targetApp
                )
            } else {
                print("Video already paused; minimizing without a playback click.")
                swipeController.performWindowButtonClick(at: event.location)
            }
            return nil
        }

        if type == .leftMouseDown,
           let targetApp = mirroringController.runningTargetApplication(),
           mirroringController.isTargetWindowInteractive(targetApp),
           NSWorkspace.shared.frontmostApplication?.processIdentifier
                != targetApp.processIdentifier,
           let frame = mirroringController.focusedWindowFrame(of: targetApp),
           frame.contains(event.location) {
            consumeNextLeftMouseUp = true
            let clickPoint = event.location
            updatePlaybackStateForUserClick(at: clickPoint, in: frame)
            let activated = mirroringController.activateTargetApplication()
            swipeController.performFocusClick(at: clickPoint)
            print(
                "Floating preview global click:\n"
                    + "  point = \(pointDescription(clickPoint))\n"
                    + "  activated iPhone Mirroring = \(activated)"
            )
            return nil
        }

        // Any direct interaction with the mirrored iPhone can navigate away
        // from the feed (for example, tapping Search or Messages). Disable
        // shortcuts immediately; OCR may enable the precise page again only
        // after both 首页 and 推荐 are visible.
        if type == .leftMouseDown,
           let targetApp = mirroringController.frontmostTargetApplication(),
           let frame = mirroringController.focusedWindowFrame(of: targetApp),
           frame.contains(event.location) {
            updatePlaybackStateForUserClick(at: event.location, in: frame)
            if pageContextDetector.isSharePageOrRecentlyConfirmed() {
                // Keep Enter enabled when the user selects a recipient with
                // the mouse. OCR will clear this as soon as the feed returns.
                shareSelectionStartedUptime = ProcessInfo.processInfo.systemUptime
                print("Direct interaction retained confirmed share-sheet context.")
            } else {
                pageContextDetector.invalidate(reason: "direct interaction with iPhone Mirroring")
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
            }
        }

        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if type == .keyDown,
               [config.nextVideoKeyCode, config.previousVideoKeyCode, 123, 124, 125, 126]
                    .contains(keyCode) {
                print("Raw navigation key received at HID tap: code = \(keyCode)")
            }

            let isWindowShortcut = config.pauseBeforeMinimizeOrHide
                && event.flags.contains(.maskCommand)
                && (keyCode == config.minimizeKeyCode || keyCode == config.hideKeyCode)
            if isWindowShortcut {
                if type == .keyUp {
                    if consumedKeyboardKeyUps.remove(keyCode) != nil { return nil }
                    return Unmanaged.passUnretained(event)
                }
                if let targetApp = mirroringController.frontmostTargetApplication(),
                   pageContextDetector.isVideoPageOrRecentlyConfirmed() {
                    NotificationCenter.default.post(
                        name: .iPhoneScrollControlWillSuspendTarget,
                        object: nil
                    )
                    consumedKeyboardKeyUps.insert(keyCode)
                    if videoIsPlaying {
                        videoIsPlaying = false
                        swipeController.pauseThenPerformSystemShortcut(
                            keyCode: keyCode,
                            app: targetApp
                        )
                    } else {
                        print("Video already paused; hiding/minimizing without a playback click.")
                        swipeController.performSystemShortcut(keyCode: keyCode)
                    }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            if type == .keyDown,
               let shareStarted = shareSelectionStartedUptime,
               ProcessInfo.processInfo.systemUptime - shareStarted
                    < config.shareSelectionTimeout {
                print("Key pressed while share selection is active: code = \(keyCode)")
            }
            let isNextVideoKey = keyCode == config.nextVideoKeyCode
                || config.nextVideoAlternateKeyCodes.contains(keyCode)
            let isPreviousVideoKey = keyCode == config.previousVideoKeyCode
                || config.previousVideoAlternateKeyCodes.contains(keyCode)
            let isLikeKey = keyCode == config.likeKeyCode
                || config.likeAlternateKeyCodes.contains(keyCode)
            let isShareKey = keyCode == config.shareKeyCode
                || config.shareAlternateKeyCodes.contains(keyCode)
            let isArrowControlKey = config.enableArrowKeyControl
                && (isNextVideoKey || isPreviousVideoKey)
            let isSpaceControlKey = config.enableSpacePlayPause
                && keyCode == config.playPauseKeyCode
            let isLikeOrShareKey = config.enableLikeAndShareKeys
                && (isLikeKey || isShareKey)
            let recipientIndex = config.shareRecipientKeyCodes[keyCode]
            let isShareSendKey = config.shareSendKeyCodes.contains(keyCode)

            let isPotentialControlKey = isArrowControlKey || isSpaceControlKey
                || isLikeOrShareKey || recipientIndex != nil || isShareSendKey

            // Ordinary typing is another strong sign that the user is in a
            // text field. Suspend first so a following Space or arrow key is
            // guaranteed to remain normal input while OCR catches up.
            if type == .keyDown,
               !isPotentialControlKey,
               mirroringController.frontmostTargetApplication() != nil {
                NativeScrollCalibration.shared.cancelCapture()
                textInputProtectionUntil = ProcessInfo.processInfo.systemUptime
                    + config.textInputProtectionInterval
                pageContextDetector.invalidate(reason: "ordinary keyboard input")
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
            }

            guard isPotentialControlKey else {
                return Unmanaged.passUnretained(event)
            }

            if type == .keyUp {
                if consumedKeyboardKeyUps.remove(keyCode) != nil {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            guard let targetApp = mirroringController.frontmostTargetApplication() else {
                return Unmanaged.passUnretained(event)
            }

            let now = ProcessInfo.processInfo.systemUptime
            let shareSelectionIsActive = shareSelectionStartedUptime.map {
                now - $0 < config.shareSelectionTimeout
            } ?? false
            let pageKind = pageContextDetector.currentPageKind()

            // A Chinese input method uses Space to commit the current
            // candidate and arrows/numbers to choose candidates. Once ordinary
            // typing is observed, pass all of those keys through for a short
            // quiet period. The share sheet is exempt because its 1-5/Enter
            // controls are deliberately enabled there.
            if now < textInputProtectionUntil {
                let remaining = textInputProtectionUntil - now
                print(
                    String(
                        format: "Keyboard key passed through: text input protection active (%.2fs remaining).",
                        remaining
                    )
                )
                return Unmanaged.passUnretained(event)
            }

            print(
                "Keyboard control key down: code = \(keyCode), "
                    + "page = \(pageKind.rawValue), "
                    + "share active = \(shareSelectionIsActive)"
            )

            // Playback controls require the exact 首页 + 推荐 feed. Recipient
            // numbers and Enter require the share sheet to be visible; a stale
            // timeout alone must never consume input on search or chat pages.
            let sharePageConfirmed = pageContextDetector.isSharePageOrRecentlyConfirmed()
            let validShareAction = sharePageConfirmed
                && (recipientIndex != nil || isShareSendKey)
            let validShareClose = sharePageConfirmed && isShareKey
            // Animated captions and bullet comments can make Vision miss 首页
            // or 推荐 for a single frame. Accept the short, confirmed-video
            // grace period here as well as for hide/minimize. Direct clicks and
            // ordinary typing invalidate that grace immediately, and detecting
            // the share sheet clears it, so search/chat input remains untouched.
            let validFeedAction = pageContextDetector.isVideoPageOrRecentlyConfirmed()
                && (isArrowControlKey || isSpaceControlKey || isLikeOrShareKey)
            guard validFeedAction || validShareAction || validShareClose else {
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
                print("Keyboard key passed through: shortcut is not enabled on this page.")
                return Unmanaged.passUnretained(event)
            }

            // Number keys are ordinary text unless Right Arrow has just opened
            // the share sheet.
            if !validShareAction,
               (isShareSendKey
                    || (recipientIndex != nil
                        && !isArrowControlKey
                        && !isLikeOrShareKey)) {
                return Unmanaged.passUnretained(event)
            }

            consumedKeyboardKeyUps.insert(keyCode)

            // Suppress macOS key-repeat so holding an arrow cannot skip many videos.
            let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isAutoRepeat {
                return nil
            }

            if let lastTrigger = lastKeyboardTriggerByKey[keyCode],
               now - lastTrigger < config.debounceInterval {
                print("Ignored keyboard control \(keyCode) within debounce interval.")
                return nil
            }
            lastKeyboardTriggerByKey[keyCode] = now

            if validShareClose {
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
                print("Arrow key: Right -> close share sheet")
                swipeController.closeShareSheet(app: targetApp)
            } else if let recipientIndex, validShareAction {
                shareSelectionStartedUptime = now
                if selectedShareRecipients.contains(recipientIndex) {
                    selectedShareRecipients.remove(recipientIndex)
                } else {
                    selectedShareRecipients.insert(recipientIndex)
                }
                print(
                    "Share recipient key -> \(recipientIndex + 1); "
                        + "selected count = \(selectedShareRecipients.count)"
                )
                swipeController.selectShareRecipient(recipientIndex, app: targetApp)
            } else if isNextVideoKey && !validShareAction {
                videoIsPlaying = true
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
                print("Arrow key: Down -> next video")
                let restoreFocus = needsContentFocusBeforeSwipe
                needsContentFocusBeforeSwipe = false
                swipeController.performSwipe(
                    .up,
                    app: targetApp,
                    ensureContentFocus: restoreFocus
                )
            } else if isPreviousVideoKey {
                videoIsPlaying = true
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
                print("Arrow key: Up -> previous video")
                let restoreFocus = needsContentFocusBeforeSwipe
                needsContentFocusBeforeSwipe = false
                swipeController.performSwipe(
                    .down,
                    app: targetApp,
                    ensureContentFocus: restoreFocus
                )
            } else if keyCode == config.playPauseKeyCode {
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
                videoIsPlaying.toggle()
                print("Space key -> play/pause; now playing = \(videoIsPlaying)")
                swipeController.performCenterClick(app: targetApp)
            } else if isLikeKey {
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
                print("Arrow key: Left -> like video")
                swipeController.performLike(app: targetApp)
            } else if isShareKey {
                shareSelectionStartedUptime = now
                selectedShareRecipients.removeAll()
                print("Arrow key: Right -> open share sheet")
                swipeController.openShareSheet(app: targetApp)
            } else if let recipientIndex {
                shareSelectionStartedUptime = now
                if selectedShareRecipients.contains(recipientIndex) {
                    selectedShareRecipients.remove(recipientIndex)
                } else {
                    selectedShareRecipients.insert(recipientIndex)
                }
                print(
                    "Share recipient key -> \(recipientIndex + 1); "
                        + "selected count = \(selectedShareRecipients.count)"
                )
                swipeController.selectShareRecipient(recipientIndex, app: targetApp)
            } else if isShareSendKey {
                // A recipient may have been selected with the mouse, so the
                // local set can be empty even while the red button is enabled.
                // OCR distinguishes the two-button multi-send layout.
                let detectedCount = pageContextDetector.shareUsesMultipleSendButton() ? 2 : 1
                let count = max(selectedShareRecipients.count, detectedCount)
                print("Enter -> click share send button; inferred recipients = \(count)")
                swipeController.sendSharedVideo(selectionCount: count, app: targetApp)
                needsContentFocusBeforeSwipe = true
                shareSelectionStartedUptime = nil
                selectedShareRecipients.removeAll()
            }
            return nil
        }

        guard type == .otherMouseDown || type == .otherMouseUp else {
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        if type == .otherMouseDown {
            print("Other mouse down:\n  button = \(button)")
        } else if type == .otherMouseUp {
            print("Other mouse up:\n  button = \(button)")
        }

        guard let targetApp = mirroringController.frontmostTargetApplication() else {
            // Preserve normal browser Back/Forward behavior everywhere else.
            return Unmanaged.passUnretained(event)
        }

        guard pageContextDetector.isVideoPageOrRecentlyConfirmed() else {
            // Side buttons also remain untouched in chat and other iPhone pages.
            return Unmanaged.passUnretained(event)
        }

        let isConfiguredButton = button == config.nextButton
            || button == config.previousButton
            || (config.enableMiddleClickPlayPause && button == config.middleButton)
        guard isConfiguredButton else {
            return Unmanaged.passUnretained(event)
        }

        // Consume both halves of a configured click while iPhone Mirroring is frontmost,
        // but trigger the action only on mouse-down.
        guard type == .otherMouseDown else { return nil }

        let now = ProcessInfo.processInfo.systemUptime
        if let previousTime = lastTriggerByButton[button],
           now - previousTime < config.debounceInterval {
            print("Ignored duplicate button \(button) within debounce interval.")
            return nil
        }
        lastTriggerByButton[button] = now

        if button == config.nextButton {
            videoIsPlaying = true
            let restoreFocus = needsContentFocusBeforeSwipe
            needsContentFocusBeforeSwipe = false
            swipeController.performSwipe(
                .up,
                app: targetApp,
                ensureContentFocus: restoreFocus
            )
        } else if button == config.previousButton {
            videoIsPlaying = true
            let restoreFocus = needsContentFocusBeforeSwipe
            needsContentFocusBeforeSwipe = false
            swipeController.performSwipe(
                .down,
                app: targetApp,
                ensureContentFocus: restoreFocus
            )
        } else if config.enableMiddleClickPlayPause && button == config.middleButton {
            videoIsPlaying.toggle()
            swipeController.performCenterClick(app: targetApp)
        }

        return nil
    }

    private func updatePlaybackStateForUserClick(at point: CGPoint, in frame: CGRect) {
        guard pageContextDetector.currentPageKind() == .video,
              frame.width > 0, frame.height > 0 else { return }
        let x = (point.x - frame.minX) / frame.width
        let y = (point.y - frame.minY) / frame.height
        // Exclude top navigation, bottom tabs, and the right-side action rail.
        // A single tap in the main video body toggles Douyin playback.
        guard (0.20...0.80).contains(x), (0.25...0.65).contains(y) else { return }
        videoIsPlaying.toggle()
        print("Direct video tap; now playing = \(videoIsPlaying).")
    }

    private func isTargetFrontmostWithoutLogging() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if let bundleID = app.bundleIdentifier,
           config.allowedBundleIdentifiers.contains(bundleID) {
            return true
        }
        if let name = app.localizedName,
           config.allowedApplicationNames.contains(name) {
            return true
        }
        return false
    }

    private func refreshScrollTargetSnapshot() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let app = NSWorkspace.shared.frontmostApplication,
              !app.isHidden,
              !app.isTerminated else {
            clearScrollTargetSnapshot()
            return
        }
        let bundleMatches = app.bundleIdentifier.map {
            config.allowedBundleIdentifiers.contains($0)
        } ?? false
        let nameMatches = app.localizedName.map {
            config.allowedApplicationNames.contains($0)
        } ?? false
        guard bundleMatches || nameMatches,
              mirroringController.isTargetWindowInteractive(app),
              let frame = mirroringController.focusedWindowFrame(of: app),
              frame.width > 0, frame.height > 0 else {
            clearScrollTargetSnapshot()
            return
        }
        if let previous = scrollTargetSnapshot,
           previous.app.processIdentifier != app.processIdentifier {
            NativeScrollCalibration.shared.cancelCapture()
        }
        scrollTargetSnapshot = ScrollTargetSnapshot(
            app: app, frame: frame, capturedUptime: now
        )
    }

    private func clearScrollTargetSnapshot() {
        scrollTargetSnapshot = nil
        NativeScrollCalibration.shared.cancelCapture()
    }
}

// MARK: - Startup

setbuf(stdout, nil)
setbuf(stderr, nil)

let config = Config()

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let promptOptions = [promptKey: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(promptOptions) {
    print("Accessibility permission required.")
    print("Grant access in System Settings > Privacy & Security > Accessibility, then restart this program.")
}
print("Permission preflight: accessibility=\(AXIsProcessTrusted()), inputMonitoring=\(CGPreflightListenEventAccess()), screenRecording=\(CGPreflightScreenCaptureAccess())")

if let app = NSWorkspace.shared.frontmostApplication {
    print("Frontmost app at launch:\n  \(app.localizedName ?? "(unknown name)")\n  \(app.bundleIdentifier ?? "(no bundle identifier)")")
}

let mirroringController = IPhoneMirroringController(config: config)
let pageContextDetector = PageContextDetector(config: config)
let alwaysOnTopController = AlwaysOnTopController(
    config: config,
    mirroringController: mirroringController
)
let floatingPreviewController = FloatingPreviewController(
    config: config,
    mirroringController: mirroringController,
    pageContextDetector: pageContextDetector
)
let swipeController = SwipeController(
    config: config,
    mirroringController: mirroringController,
    pageContextDetector: pageContextDetector
)
let mouseMonitor = MouseEventMonitor(
    config: config,
    mirroringController: mirroringController,
    swipeController: swipeController,
    pageContextDetector: pageContextDetector
)

guard mouseMonitor.start() else {
    exit(EXIT_FAILURE)
}

var alwaysOnTopTimer: Timer?
if config.keepMirroringWindowOnTop {
    alwaysOnTopController.refresh()
    alwaysOnTopTimer = Timer.scheduledTimer(
        withTimeInterval: config.alwaysOnTopRefreshInterval,
        repeats: true
    ) { _ in
        alwaysOnTopController.refresh()
    }
    print("Always-on-top monitoring enabled.")
}

if config.enableFloatingLivePreview {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    floatingPreviewController.start()
}

signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler {
    alwaysOnTopController.restoreNormalWindowLevel()
    floatingPreviewController.stop()
    exit(EXIT_SUCCESS)
}
terminationSource.resume()

print("Configuration:")
print("  nextButton = \(config.nextButton)")
print("  previousButton = \(config.previousButton)")
print("  middle click enabled = \(config.enableMiddleClickPlayPause)")
print("  scroll fallback enabled = \(config.useScrollWheelFallback)")
print("  keep iPhone Mirroring on top = \(config.keepMirroringWindowOnTop)")
print("  floating live preview = \(config.enableFloatingLivePreview)")
print("  arrow key control = \(config.enableArrowKeyControl)")
print("  space play/pause = \(config.enableSpacePlayPause)")
print("  left/right like-share control = \(config.enableLikeAndShareKeys)")
print("Press Control-C to quit.")
CFRunLoopRun()
