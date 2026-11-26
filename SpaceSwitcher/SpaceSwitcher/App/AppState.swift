import AppKit
import SwiftUI

/// Stable settings domain independent of whether Xcode launched
/// SpaceSwitcher.app or the installer launched the re-signed Spaces.app.
@MainActor
private enum SpacesPreferences {
    static let store = UserDefaults(suiteName: "com.spaceswitcher.Spaces") ?? .standard

    static func bool(_ key: String, legacy: String? = nil, fallback: Bool) -> Bool {
        if let value = store.object(forKey: key) as? Bool { return value }
        if let old = legacy,
           let value = store.object(forKey: old) as? Bool { return value }
        if let value = UserDefaults.standard.object(forKey: key) as? Bool { return value }
        if let old = legacy,
           let value = UserDefaults.standard.object(forKey: old) as? Bool { return value }
        return fallback
    }

    static func string(_ key: String) -> String? {
        store.string(forKey: key) ?? UserDefaults.standard.string(forKey: key)
    }
}

@MainActor
@Observable
final class AppState {
    var groups: [DesktopGroup] = []
    var monitors: [MonitorInfo] = []
    var activeGroupID: UUID?

    var followEnabled: Bool = SpacesPreferences.bool("gestureFollowEnabled", fallback: true) {
        didSet { SpacesPreferences.store.set(followEnabled, forKey: "gestureFollowEnabled") }
    }

    // Enabled by default, but independently switchable in Settings.
    // Only activates for apps with exactly one normal window in one uniquely mapped group.
    var followActivatedAppEnabled: Bool = SpacesPreferences.bool("followActivatedAppEnabled", fallback: true) {
        didSet { SpacesPreferences.store.set(followActivatedAppEnabled, forKey: "followActivatedAppEnabled") }
    }

    // Cmd+Tab replacement is opt-in and persists across launches.
    var replaceCommandTab: Bool = SpacesPreferences.bool(
        "cmdTabReplacementEnabled", legacy: "replaceCommandTab", fallback: false
    ) {
        didSet {
            SpacesPreferences.store.set(replaceCommandTab, forKey: "cmdTabReplacementEnabled")
            NotificationCenter.default.post(name: .commandTabSettingChanged, object: nil)
        }
    }
    var commandTabStatus = "Native macOS Cmd+Tab"

    var dockLockEnabled: Bool = SpacesPreferences.bool(
        "safeDockLockEnabled", fallback: false
    ) {
        didSet {
            SpacesPreferences.store.set(dockLockEnabled, forKey: "safeDockLockEnabled")
            refreshDockLock()
        }
    }
    var dockLockDisplayUUID: String = SpacesPreferences.string("dockLockDisplayUUID") ?? "" {
        didSet {
            SpacesPreferences.store.set(dockLockDisplayUUID, forKey: "dockLockDisplayUUID")
            refreshDockLock()
        }
    }
    var dockLockStatus: String = "Off"
    private let dockEdgeGuard = DockEdgeGuard()

    private var follower = GestureFollower()
    private var lastCurrentSpaces: CurrentSpaces = [:]
    private var lastSpaceChangeAt: TimeInterval = -10
    private var activationSequence = 0
    // Do not misidentify synthetic group switches as user swipe gestures.
    private var ignoreFollowUntil: TimeInterval = 0

    init() {
        refreshMonitors()
        // Prefer the middle monitor for three or more displays, as in the
        // default three-display VITURE setup; otherwise use the primary one.
        if dockLockDisplayUUID.isEmpty {
            let preferred = monitors.count >= 3
                ? monitors[monitors.count / 2]
                : monitors.first(where: { $0.displayID == NSScreen.screens.first?.displayID })
            dockLockDisplayUUID = preferred?.displayUUID ?? monitors.first?.displayUUID ?? ""
        }
        refreshDockLock()
        lastCurrentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
        detectActiveGroup()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        // Works with the native app switcher and AltTab; no AltTab integration required.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func spaceDidChange() {
        let old = lastCurrentSpaces
        let new = SpaceSwitcherService.getCurrentSpacePerDisplay()
        lastCurrentSpaces = new
        lastSpaceChangeAt = ProcessInfo.processInfo.systemUptime
        refreshMonitors()
        guard ProcessInfo.processInfo.systemUptime >= ignoreFollowUntil else { return }
        detectActiveGroup()

        guard followEnabled else { return }
        let requests = follower.handle(
            old: old, new: new,
            groups: followGroups(),
            now: ProcessInfo.processInfo.systemUptime
        )
        guard !requests.isEmpty else { return }
        let monitorsCopy = monitors
        Task { @MainActor in
            await SpaceSwitcherService.switchDisplays(requests, monitors: monitorsCopy)
        }
    }

    /// When switching apps, follow a single window into its containing Space group.
    /// We deliberately leave multi-window apps, sticky windows and ambiguous groups alone.
    @objc private func applicationDidActivate(_ notification: Notification) {
        activationSequence &+= 1
        let request = activationSequence
        guard followActivatedAppEnabled,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        let startedAt = ProcessInfo.processInfo.systemUptime
        guard startedAt >= ignoreFollowUntil, startedAt - lastSpaceChangeAt >= 0.4 else { return }
        let pid = app.processIdentifier

        Task { @MainActor in
            // AltTab activates the process first; give the app a moment to settle.
            try? await Task.sleep(for: .milliseconds(120))
            let now = ProcessInfo.processInfo.systemUptime
            guard request == activationSequence,
                  followActivatedAppEnabled,
                  now >= ignoreFollowUntil,
                  now - lastSpaceChangeAt >= 0.4,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let windowSpaceID = ActivatedAppWindowLocator.spaceIDForSingleWindow(processID: pid)
            else { return }

            refreshMonitors()
            detectActiveGroup()
            let groupSpaces = groups.map { group in
                monitors.compactMap { group.space(on: $0)?.spaceID }
            }
            let currentGroupIndex = groups.firstIndex { $0.id == activeGroupID }
            guard let destination = ActivatedAppGroupResolver.destinationGroupIndex(
                windowSpaceID: windowSpaceID,
                groupSpaceIDs: groupSpaces,
                currentGroupIndex: currentGroupIndex
            ) else { return }

            switchToGroup(groups[destination])
        }
    }

    private func followGroups() -> [FollowGroup] {
        groups.compactMap { group in
            var targets: [String: UInt64] = [:]
            for monitor in monitors {
                if let space = group.space(on: monitor) {
                    targets[monitor.displayUUID] = space.spaceID
                }
            }
            return targets.isEmpty ? nil : FollowGroup(id: group.id, targets: targets)
        }
    }

    /// Always rebuild the groups from native, per-monitor Desktop order.
    /// Groups do not need to be saved or manually maintained.
    func refreshMonitors() {
        monitors = MonitorManager.detectMonitors()
        let positions = AutomaticGroupLayout.indices(forSpaceCounts: monitors.map(\.spaces.count))
        let existing = groups

        groups = positions.enumerated().map { groupIndex, indices in
            let id = groupIndex < existing.count ? existing[groupIndex].id : UUID()
            var group = DesktopGroup(id: id, name: String(groupIndex + 1), icon: "Labtop")
            for (monitorIndex, spaceIndex) in indices.enumerated() {
                if let spaceIndex {
                    group.setSpaceIndex(spaceIndex, on: monitors[monitorIndex])
                }
            }
            return group
        }
        if let activeGroupID, !groups.contains(where: { $0.id == activeGroupID }) {
            self.activeGroupID = nil
        }
    }

    /// Update the guard after a monitor reconnect or when the selection changes.
    func refreshDockLock() {
        dockLockStatus = dockEdgeGuard.configure(
            enabled: dockLockEnabled, selectedDisplayUUID: dockLockDisplayUUID
        )
    }

    func cycleGroup(by offset: Int) {
        refreshMonitors()
        // During an in-flight switch, retain the requested group so rapid keypresses cycle reliably.
        if ProcessInfo.processInfo.systemUptime >= ignoreFollowUntil {
            detectActiveGroup()
        }
        let currentIndex = groups.firstIndex(where: { $0.id == activeGroupID })
        guard let nextIndex = AutomaticGroupLayout.cycledIndex(
            current: currentIndex, offset: offset, count: groups.count
        ) else { return }
        switchToGroup(groups[nextIndex])
    }

    /// Returns the in-flight operation so the app picker can wait until
    /// every monitor has completed its Space transition before focusing a window.
    @discardableResult
    func switchToGroup(_ group: DesktopGroup) -> Task<Void, Never>? {
        refreshMonitors()
        guard let target = groups.first(where: { $0.id == group.id }) else { return nil }
        activeGroupID = target.id
        // Ignore synthetic Space changes while the monitors animate/retry.
        ignoreFollowUntil = ProcessInfo.processInfo.systemUptime + 5.0
        let monitorsCopy = monitors
        return Task { @MainActor in
            await SpaceSwitcherService.switchToGroup(target, monitors: monitorsCopy)
            if self.activeGroupID == target.id {
                self.ignoreFollowUntil = ProcessInfo.processInfo.systemUptime + 0.55
                self.lastCurrentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
            }
        }
    }

    func detectActiveGroup() {
        let currentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
        for group in groups {
            let allMatch = monitors.allSatisfy { monitor in
                guard let space = group.space(on: monitor),
                      let currentID = currentSpaces[monitor.displayUUID] else {
                    return !group.hasSpace(on: monitor)
                }
                return space.spaceID == currentID
            }
            if allMatch {
                activeGroupID = group.id
                return
            }
        }
        activeGroupID = nil
    }
}
