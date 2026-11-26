import SwiftUI
import KeyboardShortcuts

struct HotkeySettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Previous group") {
                KeyboardShortcuts.Recorder(for: .previousGroup)
            }
            LabeledContent("Next group") {
                KeyboardShortcuts.Recorder(for: .nextGroup)
            }
            LabeledContent("Cycle groups") {
                KeyboardShortcuts.Recorder(for: .cycleGroup)
            }
        }
    }
}
