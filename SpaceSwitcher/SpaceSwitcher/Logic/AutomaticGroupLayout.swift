import Foundation

/// Produces synchronized groups using each monitor's *position* in its native Space list.
/// A monitor with fewer Spaces stays at its last Space.
enum AutomaticGroupLayout {
    /// For each group, the 1-based Space index on each monitor, or nil if no Spaces exist.
    static func indices(forSpaceCounts counts: [Int]) -> [[Int?]] {
        guard let maxCount = counts.max(), maxCount > 0 else { return [] }
        return (1...maxCount).map { groupNumber in
            counts.map { count in count > 0 ? min(groupNumber, count) : nil }
        }
    }

    /// Wrap at both ends. If no complete group is active, move to the first or last.
    static func cycledIndex(current: Int?, offset: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current, current >= 0, current < count else {
            return offset < 0 ? count - 1 : 0
        }
        return ((current + offset) % count + count) % count
    }
}
