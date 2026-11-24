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

        let ids = [NSNumber(value: windowIDs[0])] as CFArray
        guard let rawSpaces = copySpacesForWindows(CGSMainConnectionID(), 0x7, ids)?.takeRetainedValue(),
              let spaces = rawSpaces as? [NSNumber] else { return nil }
        let uniqueSpaceIDs = Set(spaces.map(\.uint64Value).filter { $0 != 0 })
        guard uniqueSpaceIDs.count == 1 else { return nil }
        return uniqueSpaceIDs.first
    }
}
