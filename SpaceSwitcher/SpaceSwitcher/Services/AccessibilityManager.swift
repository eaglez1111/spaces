import AppKit
import ApplicationServices

enum AccessibilityManager {
    /// Passive check: never summons a system dialog from a hotkey, gesture,
    /// or recurring background event.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Explicit recovery action, shown in Settings. Re-add
    /// /Applications/Spaces.app if a recently re-signed build is not trusted.
    @MainActor
    static func openSettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
