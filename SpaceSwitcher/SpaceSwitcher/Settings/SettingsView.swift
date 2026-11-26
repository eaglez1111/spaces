import SwiftUI
import LaunchAtLogin

struct SettingsView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        TabView {
            GroupsSettingsView()
                .tabItem { Label("Groups", systemImage: "rectangle.3.group") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 640, height: 510)
        .onAppear {
            appState.refreshMonitors()
            appState.detectActiveGroup()
        }
    }
}

struct GroupsSettingsView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automatic groups").font(.headline)
            Text("Group N uses the Nth Desktop on each monitor. Displays with fewer Desktops keep their last Desktop.")
                .foregroundStyle(.secondary).font(.caption)
            List {
                ForEach(appState.groups) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.name).font(.headline)
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(appState.monitors) { monitor in
                                if let space = group.space(on: monitor) {
                                    Text("\(monitor.label): Desktop \(space.desktopNumber)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Button("Refresh Groups") {
                appState.refreshMonitors()
                appState.detectActiveGroup()
            }
        }
        .padding()
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) var appState
    @State private var accessibilityGranted = false

    var body: some View {
        // Scroll instead of clipping the last options inside a fixed-height Form.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Keyboard shortcuts") {
                    HotkeySettingsView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }

                GroupBox("Startup and app switching") {
                    VStack(alignment: .leading, spacing: 9) {
                        LaunchAtLogin.Toggle("Launch at login")
                        Toggle("Replace Cmd+Tab with cross-Space app picker",
                               isOn: Binding(get: { appState.replaceCommandTab },
                                             set: { appState.replaceCommandTab = $0 }))
                        Text("Cmd+Tab: \(appState.commandTabStatus). Hold Command and tap Tab (or Shift+Tab); release Command to select; Esc cancels. If the macOS switcher still appears, check Input Monitoring permissions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Enable Option+Shift+Tab picker shortcut (preview)",
                               isOn: Binding(get: { appState.appPickerEnabled },
                                             set: { appState.appPickerEnabled = $0 }))
                        Text("The picker keeps Space 1 apps on the first row, Space 2 on the second. These settings now persist across relaunches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Accessibility permission") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Spaces permission:")
                            Text(accessibilityGranted ? "Granted" : "Not granted to this running build")
                                .foregroundStyle(accessibilityGranted ? .green : .orange)
                            Spacer()
                        }
                        HStack {
                            Button("Open Accessibility Settings") {
                                AccessibilityManager.openSettings()
                            }
                            Button("Input Monitoring") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            Button("Recheck Permission") {
                                accessibilityGranted = AccessibilityManager.isTrusted
                                appState.refreshDockLock()
                                NotificationCenter.default.post(
                                    name: .commandTabSettingChanged, object: nil
                                )
                            }
                        }
                        Text("If you already enabled access but this still says Not granted: remove outdated Spaces/SpaceSwitcher entries in Privacy & Security → Accessibility, add /Applications/Spaces.app, enable it, then quit and relaunch Spaces. Re-signing during installation can invalidate prior approval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Space synchronization") {
                    VStack(alignment: .leading, spacing: 9) {
                        Toggle("Follow Space changes across monitors",
                               isOn: Binding(get: { appState.followEnabled },
                                             set: { appState.followEnabled = $0 }))
                        Text("A swipe on one monitor switches the other monitors to the corresponding group.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Follow activated apps with one window",
                               isOn: Binding(get: { appState.followActivatedAppEnabled },
                                             set: { appState.followActivatedAppEnabled = $0 }))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Dock") {
                    VStack(alignment: .leading, spacing: 9) {
                        Toggle("Keep Dock at bottom of one monitor",
                               isOn: Binding(get: { appState.dockLockEnabled },
                                             set: { appState.dockLockEnabled = $0 }))
                        Picker("Dock monitor", selection: Binding(
                            get: { appState.dockLockDisplayUUID },
                            set: { appState.dockLockDisplayUUID = $0 }
                        )) {
                            ForEach(appState.monitors.filter { !$0.displayUUID.isEmpty }) { monitor in
                                Text("\(monitor.label) (\(Int(monitor.frame.width))×\(Int(monitor.frame.height)))")
                                    .tag(monitor.displayUUID)
                            }
                        }
                        Text("Dock lock: \(appState.dockLockStatus). Your checked setting and monitor selection persist after a restart. Requires Accessibility; hold Option to bypass if you need to move the Dock.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Refresh Dock lock") { appState.refreshDockLock() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .onAppear {
            accessibilityGranted = AccessibilityManager.isTrusted
        }
    }
}
