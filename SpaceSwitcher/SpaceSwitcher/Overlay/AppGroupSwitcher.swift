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
    static func list(groups: [DesktopGroup], monitors: [MonitorInfo]) -> [AppGroupEntry] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let applications = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var candidates: [AppGroupWindow] = []
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value != myPID,
                  let app = applications[owner.int32Value],
                  app.activationPolicy == .regular,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber,
                  width.doubleValue >= 80, height.doubleValue >= 60
            else { continue }

            let id = number.uint32Value
            let nativeSpaces = ActivatedAppWindowLocator.spaceIDs(forWindowID: id)
            if nativeSpaces.isEmpty { continue }
            candidates.append(AppGroupWindow(
                pid: owner.int32Value, windowID: id, spaceIDs: nativeSpaces
            ))
        }

        let nativeGroupSpaces: [[UInt64]] = groups.map { group in
            monitors.compactMap { group.space(on: $0)?.spaceID }
        }
        let choices = AppGroupCatalog.choices(
            windows: candidates, groups: nativeGroupSpaces
        )
        return choices.compactMap { choice in
            guard groups.indices.contains(choice.groupIndex),
                  let app = applications[choice.pid] else { return nil }
            let group = groups[choice.groupIndex]
            return AppGroupEntry(
                groupID: group.id,
                groupIndex: choice.groupIndex,
                groupName: group.name,
                pid: choice.pid,
                windowID: choice.windowID,
                appName: app.localizedName ?? "App",
                icon: app.icon
            )
        }
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
                                    Color.clear.frame(width: tileWidth, height: tileHeight)
                                }
                            }
                            .frame(height: tileHeight)
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
    private var selectionGeneration = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func handle(_ action: CommandTabInterceptor.Action) {
        switch action {
        case .start(let reverse):
            show(reverse: reverse)
        case .advance(let reverse):
            step(reverse: reverse)
        case .commit:
            commit()
        case .cancel:
            dismiss()
        }
    }

    private func show(reverse: Bool) {
        dismiss()
        appState.refreshMonitors()
        appState.detectActiveGroup()

        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let activeGroupID = appState.activeGroupID
        let entries = AppGroupWindowInventory.list(
            groups: appState.groups, monitors: appState.monitors
        )
        guard !entries.isEmpty else {
            // Restore the native shortcut rather than displaying an empty switcher.
            appState.replaceCommandTab = false
            appState.commandTabStatus = "No identifiable windows; native switcher restored"
            return
        }
        selection.entries = entries

        // Native Cmd+Tab starts on the entry after the currently focused app.
        let current = entries.firstIndex {
            $0.pid == frontPID && $0.groupID == activeGroupID
        }
        if let current {
            selection.selectedIndex = (current + (reverse ? entries.count - 1 : 1)) % entries.count
        } else {
            selection.selectedIndex = reverse ? entries.count - 1 : 0
        }

        let view = AppGroupSwitcherView(
            selection: selection, groupCount: appState.groups.count
        ) { [weak self] entry in
            self?.select(entry)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let window = OverlayPanel(contentRect: NSRect(origin: .zero, size: size))
        window.contentView = hosting
        window.setContentSize(size)
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            ))
        }
        window.makeKeyAndOrderFront(nil)
        panel = window
    }

    private func step(reverse: Bool) {
        guard !selection.entries.isEmpty else { return }
        let count = selection.entries.count
        selection.selectedIndex = (
            selection.selectedIndex + (reverse ? count - 1 : 1)
        ) % count
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
        if let panel {
            panel.orderOut(nil)
            panel.close()
        }
        panel = nil
    }
}
