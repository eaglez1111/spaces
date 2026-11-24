import SwiftUI
import KeyboardShortcuts

struct HotkeySettingsView: View {
    var body: some View {
        LabeledContent("Overlay Hotkey:") {
            KeyboardShortcuts.Recorder(for: .toggleOverlay)
        }
        LabeledContent("Previous Group:") {
            KeyboardShortcuts.Recorder(for: .previousGroup)
        }
        LabeledContent("Next Group:") {
            KeyboardShortcuts.Recorder(for: .nextGroup)
        }
        LabeledContent("Cycle Groups (optional):") {
            KeyboardShortcuts.Recorder(for: .cycleGroup)
        }
        Text("To use Control+Left/Right, disable the corresponding macOS Mission Control keyboard shortcuts.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
