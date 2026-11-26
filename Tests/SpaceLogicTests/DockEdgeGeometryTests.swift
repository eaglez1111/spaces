import XCTest
import Foundation
@testable import SpaceLogic

final class DockEdgeGeometryTests: XCTestCase {
    func testSideBySideGuardsOnlyUnselectedScreen() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1440, height: 900)
        ]
        let zones = DockEdgeGeometry.guardedBottomEdges(frames: frames, pinnedIndex: 0)
        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones[0].area.minX, 1440)
        XCTAssertEqual(zones[0].safeY, 891)
    }

    func testStackedScreensRemainTraversable() {
        let top = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let below = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let zones = DockEdgeGeometry.guardedBottomEdges(frames: [top, below], pinnedIndex: 1)
        XCTAssertTrue(zones.isEmpty, "The shared edge must stay open for pointer travel")
    }

    func testOnlyExposedOverhangIsGuarded() {
        let top = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let below = CGRect(x: 500, y: 900, width: 600, height: 900)
        let zones = DockEdgeGeometry.guardedBottomEdges(frames: [top, below], pinnedIndex: 1)
        XCTAssertEqual(zones.count, 2)
        XCTAssertEqual(zones[0].area.width, 500)
        XCTAssertEqual(zones[1].area.minX, 1100)
        XCTAssertEqual(zones[1].area.width, 340)
    }

    func testSingleScreenHasNoGuard() {
        XCTAssertTrue(DockEdgeGeometry.guardedBottomEdges(
            frames: [CGRect(x: 0, y: 0, width: 900, height: 600)], pinnedIndex: 0
        ).isEmpty)
    }
}
