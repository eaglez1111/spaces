import AppKit
import SwiftUI

@Observable
final class AppState {
    var groups: [DesktopGroup] = []
    var monitors: [MonitorInfo] = []
    var activeGroupID: UUID?

    var followEnabled: Bool = UserDefaults.standard.bool(forKey: "gestureFollowEnabled") {
        didSet { UserDefaults.standard.set(followEnabled, forKey: "gestureFollowEnabled") }
    }

    private var follower = GestureFollower()
    private var lastCurrentSpaces: CurrentSpaces = [:]
    // Do not misidentify synthetic group switches as user swipe gestures.
    private var ignoreFollowUntil: TimeInterval = 0

    init() {
        refreshMonitors()
        lastCurrentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
        detectActiveGroup()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func spaceDidChange() {
        let old = lastCurrentSpaces
        let new = SpaceSwitcherService.getCurrentSpacePerDisplay()
        lastCurrentSpaces = new
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
            var group = DesktopGroup(id: id, name: "Group \(groupIndex + 1)", icon: "Labtop")
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

    func switchToGroup(_ group: DesktopGroup) {
        refreshMonitors()
        guard let target = groups.first(where: { $0.id == group.id }) else { return }
        activeGroupID = target.id
        ignoreFollowUntil = ProcessInfo.processInfo.systemUptime + 1.5
        let monitorsCopy = monitors
        Task { @MainActor in
            await SpaceSwitcherService.switchToGroup(target, monitors: monitorsCopy)
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
