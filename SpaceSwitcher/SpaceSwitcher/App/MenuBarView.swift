import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(appState.groups) { group in
            Button {
                appState.switchToGroup(group)
            } label: {
                HStack {
                    Image(group.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text(group.name)
                    if appState.activeGroupID == group.id {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        if !appState.groups.isEmpty {
            Divider()
        }

        Button("Refresh Groups") {
            appState.refreshMonitors()
            appState.detectActiveGroup()
        }

        Button("Settings\u{2026}") {
            openSettings()
            NotificationCenter.default.post(name: .showSettings, object: nil)
        }

        Divider()

        Button("Quit Spaces") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

}
