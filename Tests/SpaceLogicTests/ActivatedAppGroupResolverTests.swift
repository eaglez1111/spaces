import XCTest
@testable import SpaceLogic

final class ActivatedAppGroupResolverTests: XCTestCase {
    private let groups: [[UInt64]] = [[2, 1, 4], [3, 1, 5]]

    func testNavigatesWhenOneSpaceMapsToOneOtherGroup() {
        XCTAssertEqual(ActivatedAppGroupResolver.destinationGroupIndex(windowSpaceID: 5,
            groupSpaceIDs: groups, currentGroupIndex: 0), 1)
    }

    func testDoesNotNavigateIfWindowIsAlreadyInActiveGroup() {
        XCTAssertNil(ActivatedAppGroupResolver.destinationGroupIndex(windowSpaceID: 2,
            groupSpaceIDs: groups, currentGroupIndex: 0))
    }

    func testAmbiguousRepeatedSpaceIsIgnored() {
        XCTAssertNil(ActivatedAppGroupResolver.destinationGroupIndex(windowSpaceID: 1,
            groupSpaceIDs: groups, currentGroupIndex: 0))
    }

    func testUnknownSpaceIsIgnored() {
        XCTAssertNil(ActivatedAppGroupResolver.destinationGroupIndex(windowSpaceID: 987,
            groupSpaceIDs: groups, currentGroupIndex: 0))
    }
}
