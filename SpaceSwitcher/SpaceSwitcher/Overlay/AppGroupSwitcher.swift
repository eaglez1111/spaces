import AppKit
import ApplicationServices
import SwiftUI

/// An application can appear once in several Space groups, but never twice
/// inside one group (even if it has many Chrome windows on that desktop).
struct AppGroupEntry: Identifiable {
    var id: String { "\(groupID.uuidString)-\(pid)" }
    let groupID: UUID
    let groupIndex: Int
    let groupName: String
    let pid: pid_t
    let windowID: CGWindowID
    let appName: String
    let icon: NSImage?
}

@MainActor
enum AppGroupWindowInventory {
    static func list(groups: [DesktopGroup], monitors: [MonitorInfo]) async -> [AppGroupEntry] {
        let nativeGroupSpaces: [[UInt64]] = groups.map { group in
            monitors.compactMap { group.space(on: $0)?.spaceID }
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let applications = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, NSRunningApplication)? in
                guard app.processIdentifier != myPID,
                      app.activationPolicy == .regular else { return nil }
                return (app.processIdentifier, app)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let allowedPIDs = Set(applications.keys)

        // User-triggered read-only lookups run on a background thread.
        // Never block a global keyboard event tap or replace macOS Cmd+Tab.
        let choices = await Task.detached(priority: .userInitiated) {
            Self.scan(nativeGroupSpaces: nativeGroupSpaces, allowedPIDs: allowedPIDs)
        }.value

        return choices.compactMap { choice in
            guard groups.indices.contains(choice.groupIndex),
                  let app = applications[choice.pid] else { return nil }
            let group = groups[choice.groupIndex]
            return AppGroupEntry(
                groupID: group.id, groupIndex: choice.groupIndex,
                groupName: group.name, pid: choice.pid, windowID: choice.windowID,
                appName: app.localizedName ?? "App", icon: app.icon
            )
        }
    }

    private nonisolated static func scan(
        nativeGroupSpaces: [[UInt64]], allowedPIDs: Set<pid_t>
    ) -> [AppGroupChoice] {
        let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []

        var candidates: [AppGroupWindow] = []
        var seenWindowIDs: Set<UInt32> = []
        var inspected = 0
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  allowedPIDs.contains(owner.int32Value),
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber,
                  width.doubleValue >= 80, height.doubleValue >= 60
            else { continue }

            guard inspected < 150 else { break }
            inspected += 1
            let id = number.uint32Value
            let spaces = ActivatedAppWindowLocator.spaceIDs(forWindowID: id)
            guard !spaces.isEmpty, seenWindowIDs.insert(id).inserted else { continue }
            candidates.append(AppGroupWindow(
                pid: owner.int32Value, windowID: id, spaceIDs: spaces
            ))
        }

        // CGWindowList may omit windows on an INACTIVE desktop. AXWindows can
        // expose those windows without switching Spaces. Fetch them on the
        // background task with a short per-app timeout; never on an input tap.
        // Restrict work to regular running applications and 120 AX windows.
        var inspectedAX = 0
        for pid in allowedPIDs.sorted().prefix(45) {
            guard inspectedAX < 120 else { break }
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.15)
            var rawWindows: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                axApp, kAXWindowsAttribute as CFString, &rawWindows
            ) == .success, let axWindows = rawWindows as? [AXUIElement] else {
                continue
            }

            for window in axWindows.prefix(12) {
                guard inspectedAX < 120 else { break }
                inspectedAX += 1
                var windowID: CGWindowID = 0
                guard AXWindowNumber(window, &windowID) == .success,
                      windowID > 0, !seenWindowIDs.contains(windowID) else {
                    continue
                }
                let spaces = ActivatedAppWindowLocator.spaceIDs(forWindowID: windowID)
                guard !spaces.isEmpty else { continue }
                seenWindowIDs.insert(windowID)
                candidates.append(AppGroupWindow(
                    pid: pid, windowID: windowID, spaceIDs: spaces
                ))
            }
        }

        return AppGroupCatalog.choices(
            windows: candidates, groups: nativeGroupSpaces
        )
    }
}

@Observable
@MainActor
final class AppGroupSwitcherSelection {
    var entries: [AppGroupEntry] = []
    var selectedIndex = 0
}

/// macOS-style icon tiles: one horizontal row for each Space group.
/// The selected app's name appears once below the icons, with no group labels.
struct AppGroupSwitcherView: View {
    @Bindable var selection: AppGroupSwitcherSelection
    let groupCount: Int
    let onChoose: (AppGroupEntry) -> Void

    private let tileWidth: CGFloat = 74
    private let tileHeight: CGFloat = 78
    private let tileGap: CGFloat = 8

    private var longestRow: Int {
        (0..<groupCount).map { groupIndex in
            selection.entries.filter { $0.groupIndex == groupIndex }.count
        }.max() ?? 0
    }

    private var stripWidth: CGFloat {
        min(max(CGFloat(longestRow) * (tileWidth + tileGap) + 20, 250), 1000)
    }

    private var stripHeight: CGFloat {
        min(CGFloat(max(groupCount, 1)) * tileHeight
            + CGFloat(max(groupCount - 1, 0)) * 10 + 24, 520)
    }

    private var selectedEntry: AppGroupEntry? {
        guard selection.entries.indices.contains(selection.selectedIndex) else { return nil }
        return selection.entries[selection.selectedIndex]
    }

    var body: some View {
        ScrollViewReader { scroller in
            VStack(spacing: 8) {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<groupCount, id: \.self) { groupIndex in
                            let rowEntries = selection.entries.filter {
                                $0.groupIndex == groupIndex
                            }
                            HStack(spacing: tileGap) {
                                ForEach(rowEntries) { entry in
                                    let isSelected = selectedEntry?.id == entry.id
                                    Button {
                                        onChoose(entry)
                                    } label: {
                                        GroupedAppIcon(entry: entry, isSelected: isSelected)
                                    }
                                    .buttonStyle(.plain)
                                    .help(entry.appName)
                                    .accessibilityLabel(entry.appName)
                                    .id(entry.id)
                                }
                                if rowEntries.isEmpty {
                                    Text("No detected apps")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.45))
                                        .frame(width: 130, height: tileHeight)
                                }
                            }
                            .frame(height: tileHeight)
                            .overlay(alignment: .bottom) {
                                if groupIndex < groupCount - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.16))
                                        .frame(height: 1)
                                        .offset(y: 5)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(width: stripWidth, height: stripHeight)

                Text(selectedEntry?.appName ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .frame(width: stripWidth)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.17).opacity(0.96))
            )
            .onChange(of: selection.selectedIndex) { _, index in
                guard selection.entries.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.10)) {
                    scroller.scrollTo(selection.entries[index].id, anchor: .center)
                }
            }
        }
    }
}

private struct GroupedAppIcon: View {
    let entry: AppGroupEntry
    let isSelected: Bool

    var body: some View {
        Group {
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 54, height: 54)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 74, height: 78)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.white.opacity(0.20) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(isSelected ? 0.28 : 0), lineWidth: 1)
        )
    }
}

// One private helper to match a CGWindowID to its AX window when possible.
// Merely activating Chrome can select the wrong Chrome window otherwise.
@_silgen_name("_AXUIElementGetWindow")
private func AXWindowNumber(_ element: AXUIElement, _ outID: UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor
enum AppGroupWindowFocus {
    static func raise(_ entry: AppGroupEntry) {
        guard let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        if app.isHidden { app.unhide() }
        app.activate()

        let axApp = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXWindowsAttribute as CFString, &raw
        ) == .success,
              let windows = raw as? [AXUIElement] else { return }

        for window in windows {
            var number: CGWindowID = 0
            guard AXWindowNumber(window, &number) == .success,
                  number == entry.windowID else { continue }
            AXUIElementSetAttributeValue(
                window, kAXMainAttribute as CFString, kCFBooleanTrue
            )
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                axApp, kAXFocusedWindowAttribute as CFString, window
            )
            return
        }
    }
}

@MainActor
final class AppGroupSwitcherController {
    private let appState: AppState
    private let selection = AppGroupSwitcherSelection()
    private var panel: OverlayPanel?
    private var keyMonitor: Any?
    private var showGeneration = 0
    private var loading = false
    private var selectionGeneration = 0
    // Cmd+Tab can be released before the background window scan completes.
    private var queuedSteps: [Bool] = []
    private var commitWhenReady = false

    init(appState: AppState) {
        self.appState = appState
    }

    func openOrAdvance() {
        if panel != nil {
            step(reverse: false)
        } else if !loading {
            show()
        }
    }

    func handle(_ action: CommandTabInterceptor.Action) {
        switch action {
        case .start(let reverse):
            show()
            queuedSteps.append(reverse) // native Cmd+Tab selects next/previous
        case .advance(let reverse):
            if loading {
                queuedSteps.append(reverse)
            } else {
                step(reverse: reverse)
            }
        case .commit:
            if loading {
                commitWhenReady = true
            } else {
                commit()
            }
        case .cancel:
            dismiss()
        }
    }

    private func show() {
        dismiss()
        loading = true
        appState.refreshMonitors()
        appState.detectActiveGroup()
        let groups = appState.groups
        let monitors = appState.monitors
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let activeID = appState.activeGroupID
        let generation = showGeneration

        Task { [weak self] in
            let entries = await AppGroupWindowInventory.list(groups: groups, monitors: monitors)
            guard let self, self.showGeneration == generation else { return }
            self.loading = false
            self.present(entries, groupCount: groups.count,
                         frontPID: frontPID, activeID: activeID)
        }
    }

    private func present(
        _ entries: [AppGroupEntry], groupCount: Int,
        frontPID: pid_t?, activeID: UUID?
    ) {
        // Every group keeps its assigned row: Space 1 on top,
        // Space 2 below, Space 3 below that, even if a row is empty.
        selection.entries = entries
        let current = entries.firstIndex {
            $0.pid == frontPID && $0.groupID == activeID
        }
        selection.selectedIndex = current ?? 0

        let view = AppGroupSwitcherView(
            selection: selection, groupCount: groupCount
        ) { [weak self] entry in
            self?.select(entry)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let window = OverlayPanel(contentRect: NSRect(origin: .zero, size: size))
        window.contentView = hosting
        window.setContentSize(size)

        let dockDisplayID = appState.monitors.first {
            $0.displayUUID == appState.dockLockDisplayUUID
        }?.displayID
        let screen = NSScreen.screens.first { $0.displayID == dockDisplayID }
            ?? NSScreen.screens.first
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            ))
        }
        window.makeKeyAndOrderFront(nil)
        panel = window

        // Apply keys received while scanning. On a quick Cmd+Tab tap,
        // complete the choice once the inventory arrives.
        let steps = queuedSteps
        queuedSteps.removeAll()
        for reverse in steps { step(reverse: reverse) }
        if commitWhenReady {
            commitWhenReady = false
            commit()
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53: // Escape
            dismiss()
        case 36, 76: // Return
            commit()
        case 48: // Tab
            step(reverse: event.modifierFlags.contains(.shift))
        case 123: // Left
            stepInRow(offset: -1)
        case 124: // Right
            stepInRow(offset: 1)
        case 125: // Down
            moveRow(offset: 1)
        case 126: // Up
            moveRow(offset: -1)
        default:
            return false
        }
        return true
    }

    private func step(reverse: Bool) {
        let count = selection.entries.count
        guard count > 0 else { return }
        selection.selectedIndex = (
            selection.selectedIndex + (reverse ? count - 1 : 1)
        ) % count
    }

    private func stepInRow(offset: Int) {
        guard selection.entries.indices.contains(selection.selectedIndex) else { return }
        let row = selection.entries[selection.selectedIndex].groupIndex
        let rowIndices = selection.entries.indices.filter {
            selection.entries[$0].groupIndex == row
        }
        guard let position = rowIndices.firstIndex(of: selection.selectedIndex),
              !rowIndices.isEmpty else { return }
        selection.selectedIndex = rowIndices[
            (position + offset + rowIndices.count) % rowIndices.count
        ]
    }

    private func moveRow(offset: Int) {
        guard selection.entries.indices.contains(selection.selectedIndex) else { return }
        let currentRow = selection.entries[selection.selectedIndex].groupIndex
        let allRows = Set(selection.entries.map(\.groupIndex)).sorted()
        guard allRows.count > 1,
              let rowPosition = allRows.firstIndex(of: currentRow) else { return }
        let currentIndices = selection.entries.indices.filter {
            selection.entries[$0].groupIndex == currentRow
        }
        let column = currentIndices.firstIndex(of: selection.selectedIndex) ?? 0
        let targetRow = allRows[
            (rowPosition + offset + allRows.count) % allRows.count
        ]
        let targetIndices = selection.entries.indices.filter {
            selection.entries[$0].groupIndex == targetRow
        }
        guard !targetIndices.isEmpty else { return }
        selection.selectedIndex = targetIndices[min(column, targetIndices.count - 1)]
    }

    private func commit() {
        guard selection.entries.indices.contains(selection.selectedIndex) else {
            dismiss()
            return
        }
        select(selection.entries[selection.selectedIndex])
    }

    private func select(_ entry: AppGroupEntry) {
        dismiss()
        let currentlyActive = appState.activeGroupID == entry.groupID
        if !currentlyActive,
           let target = appState.groups.first(where: { $0.id == entry.groupID }) {
            appState.switchToGroup(target)
        }

        selectionGeneration += 1
        let generation = selectionGeneration
        Task { @MainActor in
            if !currentlyActive {
                try? await Task.sleep(for: .milliseconds(320))
            }
            guard generation == selectionGeneration else { return }
            AppGroupWindowFocus.raise(entry)
        }
    }

    private func dismiss() {
        showGeneration += 1
        loading = false
        queuedSteps.removeAll()
        commitWhenReady = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let panel {
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
    }
}
