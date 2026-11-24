import Foundation

/// Maps a single ordinary app window's native Space to exactly one synchronized group.
/// Ambiguous matches (including monitors which repeat their final Space) are ignored.
enum ActivatedAppGroupResolver {
    static func destinationGroupIndex(windowSpaceID: UInt64, groupSpaceIDs: [[UInt64]], currentGroupIndex: Int?) -> Int? {
        let matches = groupSpaceIDs.enumerated().compactMap { index, spaceIDs in
            spaceIDs.contains(windowSpaceID) ? index : nil
        }
        guard matches.count == 1,
              let index = matches.first,
              index != currentGroupIndex else { return nil }
        return index
    }
}
