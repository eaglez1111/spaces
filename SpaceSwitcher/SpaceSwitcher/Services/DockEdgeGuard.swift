import AppKit
import ApplicationServices
import CoreGraphics

// Technique adapted for Spaces from DockPin (MIT, Copyright (c) 2026 Meti Kadriu).
// https://github.com/metikadriuu/DockPin — see THIRD_PARTY_NOTICES.md.
// Only intercepts pointer movement near *exposed* bottom edges of non-selected displays.
// It never changes Dock preferences, restarts Dock, or moves the pointer between displays.
final class DockEdgeGuard {
    private var zones: [DockBottomGuardZone] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    deinit { stop() }

    /// Runs on the main thread. The event tap is installed on the same run loop.
    @discardableResult
    func configure(enabled: Bool, selectedDisplayUUID: String) -> String {
        stop()
        guard enabled else { return "Off" }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return "Only one monitor connected" }

        // This feature intentionally supports only the bottom Dock.
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        guard orientation == "bottom" else { return "Dock must be positioned at Bottom" }
        guard AXIsProcessTrusted() else { return "Accessibility permission required" }

        guard let selected = screens.firstIndex(where: { Self.uuid(for: $0) == selectedDisplayUUID })
        else { return "Selected monitor is disconnected" }

        // NSScreen.cgFrame and CGEvent.location use the same top-left coordinate space.
        zones = DockEdgeGeometry.guardedBottomEdges(
            frames: screens.map(\.cgFrame), pinnedIndex: selected
        )
        guard !zones.isEmpty else {
            return "No exposed bottom edges to guard"
        }

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, rawContext in
            guard let rawContext else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DockEdgeGuard>.fromOpaque(rawContext).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }

            // Bypass when Option is held, so the Dock can still be moved deliberately.
            let modifiers = event.flags.union(CGEventSource.flagsState(.combinedSessionState))
            if modifiers.contains(.maskAlternate) { return Unmanaged.passUnretained(event) }

            let point = event.location
            for zone in controller.zones where zone.area.contains(point) {
                event.location = CGPoint(x: point.x, y: min(point.y, zone.safeY))
                break
            }
            return Unmanaged.passUnretained(event)
        }

        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return "Could not start mouse event guard" }

        let createdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), createdSource, .commonModes)
        tap = createdTap
        source = createdSource
        return "Active"
    }

    private static func uuid(for screen: NSScreen) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(screen.displayID) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        zones = []
    }
}
