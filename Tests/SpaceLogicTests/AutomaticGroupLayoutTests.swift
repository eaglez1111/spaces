import XCTest
@testable import SpaceLogic

final class AutomaticGroupLayoutTests: XCTestCase {
    func testTwoGroupsWithOneSpaceMonitor() {
        XCTAssertEqual(AutomaticGroupLayout.indices(forSpaceCounts: [2, 1, 2]),
                       [[1, 1, 1], [2, 1, 2]])
    }

    func testThreeGroupsUsingLastAvailableSpace() {
        XCTAssertEqual(AutomaticGroupLayout.indices(forSpaceCounts: [2, 3, 1]),
                       [[1, 1, 1], [2, 2, 1], [2, 3, 1]])
    }

    func testEmptyAndSingleMonitor() {
        XCTAssertEqual(AutomaticGroupLayout.indices(forSpaceCounts: [0, 2]),
                       [[nil, 1], [nil, 2]])
        XCTAssertEqual(AutomaticGroupLayout.indices(forSpaceCounts: [1]), [[1]])
        XCTAssertTrue(AutomaticGroupLayout.indices(forSpaceCounts: []).isEmpty)
    }

    func testCyclicNavigation() {
        XCTAssertEqual(AutomaticGroupLayout.cycledIndex(current: 0, offset: -1, count: 3), 2)
        XCTAssertEqual(AutomaticGroupLayout.cycledIndex(current: 2, offset: 1, count: 3), 0)
        XCTAssertEqual(AutomaticGroupLayout.cycledIndex(current: nil, offset: -1, count: 3), 2)
        XCTAssertEqual(AutomaticGroupLayout.cycledIndex(current: nil, offset: 1, count: 3), 0)
        XCTAssertNil(AutomaticGroupLayout.cycledIndex(current: 0, offset: 1, count: 0))
    }
}
