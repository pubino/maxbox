import XCTest
@testable import MaxBox

@MainActor
final class ActivityManagerTests: XCTestCase {
    var sut: ActivityManager!

    override func setUp() {
        super.setUp()
        sut = ActivityManager()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(sut.activities.isEmpty)
        XCTAssertNil(sut.currentActivity)
        XCTAssertFalse(sut.hasActiveWork)
        XCTAssertTrue(sut.recentActivities.isEmpty)
    }

    // MARK: - Start Activity

    func testStart_createsActivity() {
        let id = sut.start("Loading Inbox")

        XCTAssertEqual(sut.activities.count, 1)
        XCTAssertEqual(sut.activities.first?.id, id)
        XCTAssertEqual(sut.activities.first?.title, "Loading Inbox")
        XCTAssertTrue(sut.activities.first?.isActive ?? false)
        XCTAssertNil(sut.activities.first?.total)
    }

    func testStart_withTotal() {
        let id = sut.start("Fetching messages", total: 50)

        XCTAssertEqual(sut.activities.first?.total, 50)
        XCTAssertEqual(sut.activities.first?.current, 0)
        _ = id
    }

    func testStart_insertsAtFront() {
        sut.start("First")
        sut.start("Second")

        XCTAssertEqual(sut.activities.first?.title, "Second")
        XCTAssertEqual(sut.activities.last?.title, "First")
    }

    // MARK: - Update Progress

    func testUpdate_setsCurrent() {
        let id = sut.start("Loading", total: 10)

        sut.update(id, current: 5)

        XCTAssertEqual(sut.activities.first?.current, 5)
        XCTAssertEqual(sut.activities.first?.progress, 0.5)
    }

    func testUpdate_setsDetail() {
        let id = sut.start("Loading")

        sut.update(id, current: 3, detail: "Fetching message 3 of 10")

        XCTAssertEqual(sut.activities.first?.detail, "Fetching message 3 of 10")
    }

    func testUpdate_setsTotal() {
        let id = sut.start("Loading")
        XCTAssertNil(sut.activities.first?.total)

        sut.update(id, current: 0, total: 25)

        XCTAssertEqual(sut.activities.first?.total, 25)
    }

    func testUpdate_unknownId_doesNothing() {
        sut.start("Loading")
        let fakeId = UUID()

        sut.update(fakeId, current: 5)

        XCTAssertEqual(sut.activities.first?.current, 0)
    }

    // MARK: - Complete

    func testComplete_setsStatus() {
        let id = sut.start("Loading", total: 10)

        sut.complete(id)

        XCTAssertEqual(sut.activities.first?.status, .completed)
        XCTAssertNotNil(sut.activities.first?.completedAt)
        XCTAssertEqual(sut.activities.first?.current, 10) // Sets to total
        XCTAssertFalse(sut.activities.first?.isActive ?? true)
    }

    func testComplete_noLongerCurrentActivity() {
        let id = sut.start("Loading")
        XCTAssertNotNil(sut.currentActivity)

        sut.complete(id)

        XCTAssertNil(sut.currentActivity)
        XCTAssertFalse(sut.hasActiveWork)
    }

    // MARK: - Fail

    func testFail_setsErrorStatus() {
        let id = sut.start("Loading")

        sut.fail(id, error: "Network error")

        XCTAssertEqual(sut.activities.first?.status, .failed("Network error"))
        XCTAssertNotNil(sut.activities.first?.completedAt)
        XCTAssertFalse(sut.activities.first?.isActive ?? true)
    }

    // MARK: - Current Activity

    func testCurrentActivity_returnsFirstActive() {
        let id1 = sut.start("First")
        sut.complete(id1)
        sut.start("Second")

        XCTAssertEqual(sut.currentActivity?.title, "Second")
    }

    func testHasActiveWork_trueWhenActive() {
        sut.start("Loading")
        XCTAssertTrue(sut.hasActiveWork)
    }

    func testHasActiveWork_falseWhenAllComplete() {
        let id = sut.start("Loading")
        sut.complete(id)
        XCTAssertFalse(sut.hasActiveWork)
    }

    // MARK: - Clear Completed

    func testClearCompleted_removesNonActive() {
        let id1 = sut.start("Completed task")
        sut.complete(id1)
        let id2 = sut.start("Failed task")
        sut.fail(id2, error: "err")
        sut.start("Active task")

        sut.clearCompleted()

        XCTAssertEqual(sut.activities.count, 1)
        XCTAssertEqual(sut.activities.first?.title, "Active task")
    }

    // MARK: - Recent Activities

    func testRecentActivities_activeFirst() {
        let id1 = sut.start("First")
        sut.complete(id1)
        sut.start("Active")

        let recent = sut.recentActivities
        XCTAssertEqual(recent.first?.title, "Active")
    }

    // MARK: - Progress Calculation

    func testProgress_indeterminate() {
        sut.start("Loading")
        XCTAssertNil(sut.activities.first?.progress)
    }

    func testProgress_determinate() {
        let id = sut.start("Loading", total: 20)
        sut.update(id, current: 10)
        XCTAssertEqual(sut.activities.first?.progress, 0.5)
    }

    func testProgress_zeroTotal() {
        let id = sut.start("Loading", total: 0)
        sut.update(id, current: 0)
        // total of 0 should return nil (avoid division by zero)
        XCTAssertNil(sut.activities.first?.progress)
        _ = id
    }
}
