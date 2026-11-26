import AppKit
import KeyboardShortcuts
import LaunchAtLogin

extension KeyboardShortcuts.Name {
    static let toggleOverlay = Self("toggleOverlay", default: .init(.space, modifiers: .option))
    // These defaults match the Option-modified shortcuts shown in Settings.
    static let previousGroup = Self("previousGroup", default: .init(.leftArrow, modifiers: .option))
    static let nextGroup = Self("nextGroup", default: .init(.rightArrow, modifiers: .option))
    static let cycleGroup = Self("cycleGroup", default: .init(.tab, modifiers: .option))
}

extension Notification.Name {
    static let showOverlay = Notification.Name("showOverlay")
    static let showSettings = Notification.Name("showSettings")
    static let commandTabSettingChanged = Notification.Name("commandTabSettingChanged")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var overlayManager: OverlayManager?
    private var appGroupSwitcher: AppGroupSwitcherController?
    private let commandTab = CommandTabInterceptor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also recovers the system switcher after a previous crash.
        CommandTabInterceptor.restoreNativeSwitcher()

        // Apply the login default only to brand-new installations; do not
        // override a prior user's login-item choice during an app upgrade.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "didSetLaunchAtLoginDefault") == nil {
            let wasPreviouslyConfigured = [
                "gestureFollowEnabled", "followActivatedAppEnabled",
                "replaceCommandTab", "dockLockEnabled"
            ].contains { defaults.object(forKey: $0) != nil }
            if !wasPreviouslyConfigured {
                LaunchAtLogin.isEnabled = true
            }
            defaults.set(true, forKey: "didSetLaunchAtLoginDefault")
        }

        // Prompt for accessibility access only if not already granted
        AccessibilityManager.checkAndPrompt()

        // Set up overlay manager
        overlayManager = OverlayManager(appState: appState)
        appGroupSwitcher = AppGroupSwitcherController(appState: appState)
        commandTab.onAction = { [weak self] action in
            self?.appGroupSwitcher?.handle(action)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configureCommandTab),
            name: .commandTabSettingChanged,
            object: nil
        )
        configureCommandTab()

        // Register global hotkey
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) { [weak self] in
            Task { @MainActor in
                self?.overlayManager?.toggle()
            }
        }

        // Globally switch group directly. The action wraps at the ends.
        KeyboardShortcuts.onKeyUp(for: .previousGroup) { [weak self] in
            Task { @MainActor in self?.appState.cycleGroup(by: -1) }
        }
        KeyboardShortcuts.onKeyUp(for: .nextGroup) { [weak self] in
            Task { @MainActor in self?.appState.cycleGroup(by: 1) }
        }
        KeyboardShortcuts.onKeyUp(for: .cycleGroup) { [weak self] in
            Task { @MainActor in self?.appState.cycleGroup(by: 1) }
        }

        // Listen for "Show Switcher" from menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOverlay),
            name: .showOverlay,
            object: nil
        )

        // Listen for "Show Settings" requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettings),
            name: .showSettings,
            object: nil
        )

        // Monitor display configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        appState.refreshMonitors()

        // Ensure the settings window appears on the current space
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        // First run: open settings if no groups are configured
        if appState.groups.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                self.bringSettingsToFront()
            }
        }
    }

    @objc private func windowDidBecomeVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is OverlayPanel) else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    @objc private func showSettings() {
        bringSettingsToFront()
    }

    private func bringSettingsToFront() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where !(window is OverlayPanel) && window.canBecomeKey && window.isVisible {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    window.level = .normal
                }
            }
        }
    }

    @objc private func showOverlay() {
        let manager = overlayManager
        Task { @MainActor in
            manager?.show()
        }
    }

    @objc private func configureCommandTab() {
        commandTab.stop()
        guard appState.replaceCommandTab else {
            appState.commandTabStatus = "Native macOS switcher"
            return
        }
        if commandTab.start() {
            appState.commandTabStatus = "App icons grouped by Space"
        } else {
            // Keep the requested preference; the system switcher remains available.
            // Retry when the user reopens Spaces with Accessibility permission.
            appState.commandTabStatus = "Unavailable: check Accessibility, then relaunch Spaces"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandTab.stop()  // Always restore native Cmd+Tab on a normal quit.
    }

    @objc private func screensChanged() {
        appState.refreshMonitors()
        appState.detectActiveGroup()
        appState.refreshDockLock()
    }
}
