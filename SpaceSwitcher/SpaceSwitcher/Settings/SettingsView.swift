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
        .frame(width: 580, height: 400)
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
                        HStack(spacing: 12) {
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

    var body: some View {
        Form {
            HotkeySettingsView()
            LaunchAtLogin.Toggle("Launch at login")
            Toggle("Switch the whole group when a Space changes on one display (e.g. three-finger swipe)",
                   isOn: Binding(get: { appState.followEnabled }, set: { appState.followEnabled = $0 }))
        }
        .padding()
    }
}
