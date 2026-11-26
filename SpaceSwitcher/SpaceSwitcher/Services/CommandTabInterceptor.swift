import AppKit
import CoreGraphics
import Darwin

// The system Dock consumes Cmd+Tab before ordinary global hotkey handlers see it.
// The two native symbolic hotkeys are disabled ONLY while this event tap is active.
// A regular app quit, graceful SIGTERM, and the next launch restore the native shortcut.
// Do not call SkyLight from a POSIX signal handler.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult private func CGSSetSymbolicHotKeyEnabled(
    _ hotkey: Int32, _ enabled: Bool
) -> CGError

@MainActor
final class CommandTabInterceptor {
    enum Action: Sendable {
        case start(reverse: Bool)
        case advance(reverse: Bool)
        case moveHorizontal(offset: Int)
        case moveVertical(offset: Int)
        case commit
        case cancel
    }

    var onAction: (@MainActor (Action) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    private(set) var lastStartError = ""
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var cycling = false

    static func restoreNativeSwitcher() {
        _ = CGSSetSymbolicHotKeyEnabled(1, true)
        _ = CGSSetSymbolicHotKeyEnabled(2, true)
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        lastStartError = ""
        guard AXIsProcessTrusted() else {
            lastStartError = "Accessibility permission not granted to this build"
            return false
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, raw in
            guard let raw else { return Unmanaged.passUnretained(event) }
            // Installed on the main run loop. Keep the callback itself very short.
            // assumeIsolated requires a Sendable return type in Swift 6.
            // Keep the CGEvent result local and return Void across the boundary.
            var result: Unmanaged<CGEvent>?
            MainActor.assumeIsolated {
                result = Unmanaged<CommandTabInterceptor>
                    .fromOpaque(raw).takeUnretainedValue()
                    .handle(type: type, event: event)
            }
            return result
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastStartError = "Keyboard event tap unavailable (check Input Monitoring permission)"
            return false
        }

        let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        tap = newTap
        source = newSource
        // 1=Cmd+Tab, 2=Cmd+Shift+Tab. If the system won't release them,
        // leave the native switcher enabled instead of trapping the shortcut.
        let forward = CGSSetSymbolicHotKeyEnabled(1, false)
        let backward = CGSSetSymbolicHotKeyEnabled(2, false)
        guard forward == .success, backward == .success else {
            lastStartError = "System Cmd+Tab takeover failed (errors \(forward.rawValue), \(backward.rawValue))"
            stop()
            return false
        }
        return true
    }

    func stop() {
        Self.restoreNativeSwitcher()
        cycling = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
    }

    private func notify(_ action: Action) {
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Do not tear down the CFMachPort while inside its own callback.
            // Restore macOS Cmd+Tab on the next main-run-loop turn.
            DispatchQueue.main.async { [weak self] in
                self?.stop()
                self?.onError?("Keyboard tap disabled by macOS; native Cmd+Tab restored")
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            if cycling && !event.flags.contains(.maskCommand) {
                cycling = false
                notify(.commit)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let isDown = type == .keyDown

        if !cycling {
            guard code == 48 && event.flags.contains(.maskCommand) else {
                return Unmanaged.passUnretained(event)
            }
            if isDown {
                cycling = true
                notify(.start(reverse: event.flags.contains(.maskShift)))
            }
            return nil
        }

        switch code {
        case 48:  // Tab
            if isDown { notify(.advance(reverse: event.flags.contains(.maskShift))) }
        case 53:  // Escape
            if isDown {
                cycling = false
                notify(.cancel)
            }
        case 123: // left: previous app in the current Space row
            if isDown { notify(.moveHorizontal(offset: -1)) }
        case 124: // right: next app in the current Space row
            if isDown { notify(.moveHorizontal(offset: 1)) }
        case 125: // down: next Space row
            if isDown { notify(.moveVertical(offset: 1)) }
        case 126: // up: previous Space row
            if isDown { notify(.moveVertical(offset: -1)) }
        case 36, 76: // Return
            if isDown {
                cycling = false
                notify(.commit)
            }
        default:
            // Never intercept unrelated typing or shortcuts if the user
            // keeps Command down. Pass unrecognized keys through unchanged.
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}
