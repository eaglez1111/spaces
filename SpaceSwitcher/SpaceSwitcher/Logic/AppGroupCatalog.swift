import Foundation

/// One entry per application, within each synchronized Space group.
/// Windows on several Spaces may appear in several groups, but never twice in one.
struct AppGroupWindow: Equatable, Sendable {
    let pid: Int32
    let windowID: UInt32
    let spaceIDs: Set<UInt64>
}

struct AppGroupChoice: Equatable, Sendable {
    let groupIndex: Int
    let pid: Int32
    let windowID: UInt32
}

enum AppGroupCatalog {
    static func choices(windows: [AppGroupWindow], groups: [[UInt64]]) -> [AppGroupChoice] {
        var choices: [AppGroupChoice] = []
        for (groupIndex, nativeSpaces) in groups.enumerated() {
            let spaceSet = Set(nativeSpaces)
            var seenApps: Set<Int32> = []
            for window in windows {
                guard !window.spaceIDs.isDisjoint(with: spaceSet),
                      seenApps.insert(window.pid).inserted else { continue }
                choices.append(AppGroupChoice(
                    groupIndex: groupIndex, pid: window.pid, windowID: window.windowID
                ))
            }
        }
        return choices
    }
}
