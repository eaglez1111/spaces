import Foundation

/// A small area at the exposed bottom of a non-selected monitor.
/// CoreGraphics coordinate system: origin at upper-left, Y increasing downward.
struct DockBottomGuardZone {
    let area: CGRect
    let safeY: CGFloat
}

enum DockEdgeGeometry {
    /// Exclude shared edges with an adjacent display, so a stacked layout still allows
    /// the pointer to travel normally from one monitor to the next.
    static func guardedBottomEdges(
        frames: [CGRect],
        pinnedIndex: Int,
        depth: CGFloat = 7,
        adjacencyTolerance: CGFloat = 2
    ) -> [DockBottomGuardZone] {
        guard frames.indices.contains(pinnedIndex), frames.count > 1 else { return [] }
        var zones: [DockBottomGuardZone] = []

        for i in frames.indices where i != pinnedIndex {
            let frame = frames[i]
            guard frame.width > 0, frame.height > depth + 2 else { continue }
            let edge = frame.maxY

            // Portions of this bottom edge that lead immediately into another display.
            var occluded: [(CGFloat, CGFloat)] = []
            for j in frames.indices where j != i {
                let other = frames[j]
                guard abs(other.minY - edge) <= adjacencyTolerance else { continue }
                let left = max(frame.minX, other.minX)
                let right = min(frame.maxX, other.maxX)
                if right > left { occluded.append((left, right)) }
            }
            occluded.sort { $0.0 < $1.0 }

            var cursor = frame.minX
            var exposed: [(CGFloat, CGFloat)] = []
            for (start, end) in occluded {
                let clippedStart = max(frame.minX, start)
                let clippedEnd = min(frame.maxX, end)
                if clippedStart > cursor { exposed.append((cursor, clippedStart)) }
                cursor = max(cursor, clippedEnd)
            }
            if cursor < frame.maxX { exposed.append((cursor, frame.maxX)) }

            for (start, end) in exposed where end - start >= 1 {
                zones.append(DockBottomGuardZone(
                    area: CGRect(x: start, y: edge - depth, width: end - start, height: depth + 2),
                    safeY: edge - depth - 2
                ))
            }
        }

        return zones
    }
}
