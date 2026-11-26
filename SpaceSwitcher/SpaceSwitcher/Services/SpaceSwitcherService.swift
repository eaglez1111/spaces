import AppKit
import CoreGraphics
import Foundation
import Darwin
import os.log

private let logger = Logger(subsystem: "com.spaceswitcher", category: "SpaceSwitcher")

enum SpaceSwitcherService {
    private struct Target {
        let displayUUID: String
        let spaceID: UInt64
        let desktopNumber: Int
    }

    // Cancel old retry loops when the user requests a newer group.
    @MainActor private static var latestSwitch = 0

    @MainActor
    static func switchToGroup(_ group: DesktopGroup, monitors: [MonitorInfo]) async {
        latestSwitch &+= 1
        let generation = latestSwitch
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility unavailable; cannot switch group")
            return
        }

        let targets: [Target] = monitors.compactMap { monitor in
            guard !monitor.displayUUID.isEmpty,
                  let space = group.space(on: monitor) else { return nil }
            return Target(
                displayUUID: monitor.displayUUID,
                spaceID: space.spaceID,
                desktopNumber: space.desktopNumber
            )
        }
        await switchTargets(targets, generation: generation)
    }

    @MainActor
    static func switchDisplays(_ requests: [SwitchRequest], monitors: [MonitorInfo]) async {
        latestSwitch &+= 1
        let generation = latestSwitch
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility unavailable; cannot follow Space changes")
            return
        }
        let targets: [Target] = requests.compactMap { request in
            guard let monitor = monitors.first(where: {
                $0.displayUUID == request.displayUUID
            }), let space = monitor.spaces.first(where: {
                $0.spaceID == request.spaceID
            }) else { return nil }
            return Target(
                displayUUID: monitor.displayUUID,
                spaceID: request.spaceID,
                desktopNumber: space.desktopNumber
            )
        }
        await switchTargets(targets, generation: generation)
    }

    // Mission Control maps Switch to Desktop 1...16 to symbolic hotkeys 118...133.
    // macOS often leaves higher-numbered shortcuts disabled, particularly those
    // assigned to the third display. A disabled shortcut cannot be fixed by
    // posting the same Ctrl+number keystroke repeatedly.
    private typealias IsShortcutEnabled = @convention(c) (Int32) -> Bool
    @MainActor private static let shortcutEnabledFunction: IsShortcutEnabled? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "CGSIsSymbolicHotKeyEnabled") else {
            return nil // Unknown: don't assume disabled on unsupported macOS.
        }
        return unsafeBitCast(symbol, to: IsShortcutEnabled.self)
    }()

    @MainActor
    private static func systemShortcutEnabled(_ desktopNumber: Int) -> Bool? {
        guard (1...16).contains(desktopNumber),
              let check = shortcutEnabledFunction else { return nil }
        return check(Int32(117 + desktopNumber))
    }

    @MainActor
    static func disabledDesktopShortcuts(monitors: [MonitorInfo]) -> [Int] {
        let numbers = Set(monitors.flatMap { $0.spaces.map(\.desktopNumber) })
        return numbers.filter { systemShortcutEnabled($0) == false }.sorted()
    }

    // Our hotkeys are Option+Tab / Option+arrows. Sending Ctrl+N while Option
    // is physically held can turn the shortcut into Ctrl+Option+N. Wait for
    // that modifier to be released, without blocking the event/main thread.
    @MainActor
    private static func waitForModifiersToRelease(generation: Int) async -> Bool {
        for _ in 0..<150 {
            guard generation == latestSwitch, !Task.isCancelled else { return false }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if !flags.contains(.maskAlternate) && !flags.contains(.maskCommand) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        logger.warning("Modifier keys remained pressed; skipping synthetic shortcut")
        return false
    }

    /// Poll for the actual target Space IDs, returning early on fast systems.
    /// Never wait an entire animation interval when switching already finished.
    @MainActor
    private static func waitUntilReached(
        _ targets: [Target], generation: Int, maxMilliseconds: Int
    ) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime +
            Double(maxMilliseconds) / 1000.0
        repeat {
            guard generation == latestSwitch, !Task.isCancelled else { return false }
            let current = getCurrentSpacePerDisplay()
            if targets.allSatisfy({ current[$0.displayUUID] == $0.spaceID }) {
                return true
            }
            if ProcessInfo.processInfo.systemUptime >= end { break }
            try? await Task.sleep(for: .milliseconds(12))
        } while true
        return false
    }

    /// Fast first pass, followed by at most one retry for displays which
    /// still have not changed. A newer user action cancels any pending retry.
    @MainActor
    private static func switchTargets(_ targets: [Target], generation: Int) async {
        guard !targets.isEmpty,
              await waitForModifiersToRelease(generation: generation) else { return }
        for attempt in 1...2 {
            guard generation == latestSwitch, !Task.isCancelled else { return }
            let current = getCurrentSpacePerDisplay()
            let pending = targets.filter { current[$0.displayUUID] != $0.spaceID }
            if pending.isEmpty { return }

            for target in pending {
                guard generation == latestSwitch, !Task.isCancelled else { return }
                if getCurrentSpacePerDisplay()[target.displayUUID] == target.spaceID {
                    continue
                }
                if systemShortcutEnabled(target.desktopNumber) == false {
                    logger.warning(
                        "Switch to Desktop \\(target.desktopNumber) is disabled in Mission Control keyboard shortcuts"
                    )
                    continue
                }
                guard let mapping = KeyCodes.keyMapping(for: target.desktopNumber) else {
                    logger.warning("Unsupported Desktop \\(target.desktopNumber) shortcut")
                    continue
                }
                _ = postKeystroke(
                    source: CGEventSource(stateID: .combinedSessionState),
                    keyCode: mapping.keyCode,
                    flags: mapping.flags
                )
                try? await Task.sleep(for: .milliseconds(10))
            }

            // A first-pass timeout is long enough for native animations while
            // still much quicker on machines where WindowServer settles early.
            if await waitUntilReached(
                targets, generation: generation,
                maxMilliseconds: attempt == 1 ? 180 : 150
            ) { return }
        }

        let final = getCurrentSpacePerDisplay()
        for target in targets where final[target.displayUUID] != target.spaceID {
            logger.warning(
                "Display \\(target.displayUUID, privacy: .public) did not reach Desktop \\(target.desktopNumber)"
            )
        }
    }

    private static func postKeystroke(source: CGEventSource?, keyCode: UInt16, flags: CGEventFlags) -> Bool {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        logger.info("  keyDown event created: \(keyDown != nil)")
        logger.info("  keyUp event created: \(keyUp != nil)")

        guard let keyDown, let keyUp else {
            logger.error("  Failed to create CGEvent objects")
            return false
        }

        keyDown.flags = flags
        let flagsHex = String(flags.rawValue, radix: 16)
        logger.info("  Posting keyDown (keyCode=\(keyCode), flags=0x\(flagsHex, privacy: .public)) to .cghidEventTap")
        keyDown.post(tap: .cghidEventTap)

        usleep(8_000) // Short native key press; avoid unnecessary delay

        keyUp.flags = flags
        logger.info("  Posting keyUp to .cghidEventTap")
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    static func getCurrentSpacePerDisplay(connection: Int32 = CGSMainConnectionID()) -> [String: UInt64] {
        guard let displays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            logger.error("CGSCopyManagedDisplaySpaces returned nil")
            return [:]
        }

        var result: [String: UInt64] = [:]
        for display in displays {
            guard let uuid = display["Display Identifier"] as? String,
                  let currentSpace = display["Current Space"] as? [String: Any],
                  let spaceID = currentSpace["id64"] as? UInt64
            else { continue }
            result[uuid] = spaceID
        }
        return result
    }
}
