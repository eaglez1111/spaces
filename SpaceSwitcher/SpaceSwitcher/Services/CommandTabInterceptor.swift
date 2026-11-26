import AppKit
import CoreGraphics
import Darwin

// The system Dock consumes Cmd+Tab before ordinary global hotkey handlers see it.
// The two native symbolic hotkeys are disabled ONLY while this event tap is active.
// A regular app quit, SIGTERM, and the next launch all restore the native shortcut.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult private func CGSSetSymbolicHotKeyEnabled(
    _ hotkey: Int32, _ enabled: Bool
) -> CGError

private func restoreNativeSwitcherOnSignal(_ number: Int32) {
    _ = CGSSetSymbolicHotKeyEnabled(1, true)
    _ = CGSSetSymbolicHotKeyEnabled(2, true)
    signal(number, SIG_DFL)
    raise(number)
}

@MainActor
final class CommandTabInterceptor {
    enum Action: Sendable {
        case start(reverse: Bool)
        case advance(reverse: Bool)
        case commit
        case cancel
    }

    var onAction: (@MainActor (Action) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var cycling = false

    static func restoreNativeSwitcher() {
        _ = CGSSetSymbolicHotKeyEnabled(1, true)
        _ = CGSSetSymbolicHotKeyEnabled(2, true)
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, raw in
            guard let raw else { return Unmanaged.passUnretained(event) }
            // Installed on the main run loop. Keep the callback itself very short.
            return MainActor.assumeIsolated {
                Unmanaged<CommandTabInterceptor>
                    .fromOpaque(raw).takeUnretainedValue()
                    .handle(type: type, event: event)
            }
        }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

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
            stop()
            return false
        }
        signal(SIGTERM, restoreNativeSwitcherOnSignal)
        signal(SIGINT, restoreNativeSwitcherOnSignal)
        signal(SIGHUP, restoreNativeSwitcherOnSignal)
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
            // Avoid leaving Cmd+Tab swallowed when macOS disables our event tap.
            stop()
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
        case 123, 126: // left or up
            if isDown { notify(.advance(reverse: true)) }
        case 124, 125: // right or down
            if isDown { notify(.advance(reverse: false)) }
        case 36, 76: // Return
            if isDown {
                cycling = false
                notify(.commit)
            }
        default:
            break
        }
        // During the overlay, don't leak keys to the previously active app.
        return nil
    }
}
