import SwiftUI
import KeyboardShortcuts

struct HotkeySettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Group overlay").frame(width: 150, alignment: .leading)
                KeyboardShortcuts.Recorder(for: .toggleOverlay)
            }
            HStack {
                Text("Previous group").frame(width: 150, alignment: .leading)
                KeyboardShortcuts.Recorder(for: .previousGroup)
            }
            HStack {
                Text("Next group").frame(width: 150, alignment: .leading)
                KeyboardShortcuts.Recorder(for: .nextGroup)
            }
            HStack {
                Text("Cycle groups").frame(width: 150, alignment: .leading)
                KeyboardShortcuts.Recorder(for: .cycleGroup)
            }
            HStack {
                Text("App picker").frame(width: 150, alignment: .leading)
                KeyboardShortcuts.Recorder(for: .appPicker)
            }
            Text("Defaults: Option+Space, Option+Left/Right, Option+Tab; app picker: Option+Shift+Tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
