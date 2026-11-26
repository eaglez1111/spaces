import AppKit
import CoreGraphics
import Foundation
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

    /// macOS changes desktops asynchronously. The previous version sent
    /// several Ctrl+number events 5ms apart without waiting for animations.
    /// Verify the native Space ID of EACH display, retry ONLY misses, and
    /// stop after three attempts instead of flooding the input subsystem.
    @MainActor
    private static func switchTargets(_ targets: [Target], generation: Int) async {
        guard !targets.isEmpty else { return }

        for attempt in 1...3 {
            guard generation == latestSwitch, !Task.isCancelled else { return }

            let current = getCurrentSpacePerDisplay()
            let pending = targets.filter {
                current[$0.displayUUID] != $0.spaceID
            }
            if pending.isEmpty {
                logger.info("All targeted displays reached requested Spaces")
                return
            }

            logger.info("Space switch pass \(attempt): \(pending.count) displays pending")
            for target in pending {
                guard generation == latestSwitch, !Task.isCancelled else { return }
                // The previous display may still be animating. Do not send a
                // second Ctrl+N before checking what the window server reports.
                if getCurrentSpacePerDisplay()[target.displayUUID] == target.spaceID {
                    continue
                }
                guard let mapping = KeyCodes.keyMapping(for: target.desktopNumber) else {
                    logger.warning("No Space hotkey for desktop \(target.desktopNumber)")
                    continue
                }
                let source = CGEventSource(stateID: .combinedSessionState)
                let sent = postKeystroke(
                    source: source, keyCode: mapping.keyCode, flags: mapping.flags
                )
                if !sent {
                    logger.error("Could not synthesize switch to desktop \(target.desktopNumber)")
                }
                // Yield so Mission Control can finish changing this display.
                try? await Task.sleep(for: .milliseconds(380))
            }
        }

        let final = getCurrentSpacePerDisplay()
        for target in targets where final[target.displayUUID] != target.spaceID {
            logger.warning("Display \(target.displayUUID, privacy: .public) did not reach desktop \(target.desktopNumber)")
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

        usleep(30_000) // Allow key down to register before key up

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
