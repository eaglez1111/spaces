import AppKit
import CoreGraphics
import Foundation
import Darwin

/// Locate a native Space only when the newly active app has one normal window.
/// Read-only: never moves windows, manipulates Spaces directly, or accesses window titles.
enum ActivatedAppWindowLocator {
    // Private SkyLight API. Resolve at runtime and gracefully do nothing if unavailable.
    // This is the same read-only Space membership operation used by other macOS Spaces tools.
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpacesForWindows: CopySpacesForWindows? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesForWindows.self)
    }()

    // Enumerate windows directly from a native Space, including inactive Spaces.
    // This complements SLSCopySpacesForWindows, which can omit off-Space windows.
    // The window-to-Space API above takes NSNumber objects; this different API
    // expects *raw Space IDs* stored as CFArray pointer values.
    private typealias CopyWindowsForSpace = @convention(c) (
        Int32, UInt32, CFArray, UInt32,
        UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?

    private static let copyWindowsForSpace: CopyWindowsForSpace? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSCopyWindowsWithOptionsAndTags") else { return nil }
        return unsafeBitCast(symbol, to: CopyWindowsForSpace.self)
    }()

    /// Returns nil if the optional private API is unavailable; never guesses a Space.
    static func windowIDs(inSpace spaceID: UInt64) -> Set<UInt32>? {
        guard spaceID > 0, let copyWindowsForSpace else { return nil }
        var pointer: UnsafeRawPointer? = UnsafeRawPointer(bitPattern: UInt(spaceID))
        guard let input = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil) else { return nil }
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        guard let result = copyWindowsForSpace(
            CGSMainConnectionID(), 0, input, 0x7, &setTags, &clearTags
        )?.takeRetainedValue() else { return nil }

        var ids = Set<UInt32>()
        for index in 0..<CFArrayGetCount(result) {
            guard let value = CFArrayGetValueAtIndex(result, index) else { continue }
            let number = Unmanaged<CFNumber>.fromOpaque(value).takeUnretainedValue()
            var raw: Int64 = 0
            if CFNumberGetValue(number, .sInt64Type, &raw),
               raw > 0, raw <= Int64(UInt32.max) {
                ids.insert(UInt32(raw))
            }
        }
        return ids
    }

    static func spaceIDForSingleWindow(processID: pid_t) -> UInt64? {
        guard let copySpacesForWindows,
              let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        let windowIDs: [UInt32] = windows.compactMap { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == processID,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let windowNumber = window[kCGWindowNumber as String] as? NSNumber,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber,
                  width.doubleValue > 80, height.doubleValue > 60 else { return nil }
            return windowNumber.uint32Value
        }
        // If the app has several windows, we can't infer which one AltTab selected.
        guard windowIDs.count == 1 else { return nil }

        let spaces = spaceIDs(forWindowID: windowIDs[0])
        return spaces.count == 1 ? spaces.first : nil
    }

    /// Return the window's native Space memberships, including windows on other desktops.
    /// An empty result means unknown (not proof the window is on the active Space).
    static func spaceIDs(forWindowID windowID: UInt32) -> Set<UInt64> {
        guard let copySpacesForWindows else { return [] }
        let number = NSNumber(value: windowID)
        var pointers: [UnsafeRawPointer?] = [
            UnsafeRawPointer(Unmanaged.passUnretained(number).toOpaque())
        ]
        var callbacks = kCFTypeArrayCallBacks
        guard let ids = pointers.withUnsafeMutableBufferPointer({ buffer in
            CFArrayCreate(kCFAllocatorDefault, buffer.baseAddress, buffer.count, &callbacks)
        }), let rawSpaces = copySpacesForWindows(CGSMainConnectionID(), 0x7, ids)?.takeRetainedValue()
        else { return [] }

        var unique = Set<UInt64>()
        for index in 0..<CFArrayGetCount(rawSpaces) {
            guard let pointer = CFArrayGetValueAtIndex(rawSpaces, index) else { continue }
            let value = Unmanaged<CFNumber>.fromOpaque(pointer).takeUnretainedValue()
            var rawID: Int64 = 0
            if CFNumberGetValue(value, .sInt64Type, &rawID), rawID > 0 {
                unique.insert(UInt64(rawID))
            }
        }
        return unique
    }
}
