import XCTest
@testable import SpaceLogic

final class AppGroupCatalogTests: XCTestCase {
    func testSameAppOnceInEachGroup() {
        let windows = [
            AppGroupWindow(pid: 1, windowID: 10, spaceIDs: [101]),
            AppGroupWindow(pid: 2, windowID: 20, spaceIDs: [101]),
            AppGroupWindow(pid: 2, windowID: 21, spaceIDs: [201]),
            AppGroupWindow(pid: 2, windowID: 22, spaceIDs: [201]),
            AppGroupWindow(pid: 3, windowID: 30, spaceIDs: [201])
        ]
        XCTAssertEqual(AppGroupCatalog.choices(windows: windows, groups: [[101], [201]]), [
            AppGroupChoice(groupIndex: 0, pid: 1, windowID: 10),
            AppGroupChoice(groupIndex: 0, pid: 2, windowID: 20),
            AppGroupChoice(groupIndex: 1, pid: 2, windowID: 21),
            AppGroupChoice(groupIndex: 1, pid: 3, windowID: 30)
        ])
    }

    func testStickyWindowAndRepeatedSpaceHaveAnEntryInEachMatchingGroup() {
        let windows = [AppGroupWindow(pid: 1, windowID: 11, spaceIDs: [6])]
        XCTAssertEqual(AppGroupCatalog.choices(windows: windows, groups: [[2, 6], [3, 6]]).count, 2)
    }

    func testUnknownSpaceIsSkipped() {
        XCTAssertTrue(AppGroupCatalog.choices(
            windows: [AppGroupWindow(pid: 10, windowID: 5, spaceIDs: [])],
            groups: [[1], [2]]
        ).isEmpty)
    }
}
