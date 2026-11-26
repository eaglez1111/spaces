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
        .frame(width: 580, height: 430)
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
            List {
                ForEach(appState.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Group \(group.name)").fontWeight(.medium)
                        ForEach(appState.monitors) { monitor in
                            if let space = group.space(on: monitor) {
                                Text("\(monitor.label): Desktop \(space.desktopNumber)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            let disabled = SpaceSwitcherService.disabledDesktopShortcuts(monitors: appState.monitors)
            if !disabled.isEmpty {
                Label("Enable Mission Control shortcuts for Desktop " +
                      disabled.map(String.init).joined(separator: ", "),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Refresh Groups") {
                    appState.refreshMonitors()
                    appState.detectActiveGroup()
                }
            }
        }
        .padding()
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) var appState
    @State private var accessibilityGranted = false

    private var keyboardHookFailed: Bool {
        guard appState.replaceCommandTab else { return false }
        let message = appState.commandTabStatus.lowercased()
        return message.contains("unavailable") || message.contains("failed") ||
               message.contains("disabled") || message.contains("not granted")
    }

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                HotkeySettingsView()
            }
            Section("App switching") {
                Toggle("Replace Cmd+Tab", isOn: Binding(
                    get: { appState.replaceCommandTab },
                    set: { appState.replaceCommandTab = $0 }
                ))
                Toggle("Follow activated apps", isOn: Binding(
                    get: { appState.followActivatedAppEnabled },
                    set: { appState.followActivatedAppEnabled = $0 }
                ))
            }
            Section("Spaces") {
                Toggle("Synchronize Spaces across displays", isOn: Binding(
                    get: { appState.followEnabled },
                    set: { appState.followEnabled = $0 }
                ))
            }
            Section("Dock") {
                Toggle("Keep Dock on one monitor", isOn: Binding(
                    get: { appState.dockLockEnabled },
                    set: { appState.dockLockEnabled = $0 }
                ))
                Picker("Dock monitor", selection: Binding(
                    get: { appState.dockLockDisplayUUID },
                    set: { appState.dockLockDisplayUUID = $0 }
                )) {
                    ForEach(appState.monitors.filter { !$0.displayUUID.isEmpty }) { monitor in
                        Text(monitor.label).tag(monitor.displayUUID)
                    }
                }
            }
            Section("Startup") {
                LaunchAtLogin.Toggle("Launch at login")
            }
            if !accessibilityGranted {
                Section("Permission") {
                    LabeledContent("Accessibility") {
                        Button("Open System Settings…") {
                            AccessibilityManager.openSettings()
                        }
                    }
                }
            } else if keyboardHookFailed {
                Section("Keyboard access") {
                    LabeledContent("Cmd+Tab couldn't start") {
                        Button("Input Monitoring…") {
                            if let url = URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                            ) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityGranted = AccessibilityManager.isTrusted
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            let granted = AccessibilityManager.isTrusted
            if granted && !accessibilityGranted {
                appState.refreshDockLock()
                NotificationCenter.default.post(name: .commandTabSettingChanged, object: nil)
            }
            accessibilityGranted = granted
        }
    }
}
