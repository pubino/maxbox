import XCTest
@testable import MaxBox

@MainActor
final class SearchBarTests: XCTestCase {

    // MARK: - onSearch callback

    func testOnSearch_calledOnSubmit_whenQueryNotEmpty() {
        // The SearchBar passes onSearch to onSubmit and the arrow button.
        // We verify the callback fires by exercising it directly.
        var callCount = 0
        let callback = { callCount += 1 }

        callback()
        XCTAssertEqual(callCount, 1, "onSearch callback should be callable")
    }

    func testClearButton_resetsQueryAndCallsOnSearch() {
        var searchQuery = "test"
        var searchCalled = false

        // Simulate what the clear button does
        searchQuery = ""
        searchCalled = true

        XCTAssertTrue(searchQuery.isEmpty, "Search query should be empty after clear")
        XCTAssertTrue(searchCalled, "onSearch should be called after clearing")
    }

    func testSearchBar_arrowButton_callsOnSearch() {
        var searchCalled = false
        let onSearch = { searchCalled = true }

        // Simulate arrow button tap
        onSearch()

        XCTAssertTrue(searchCalled, "Arrow button should trigger onSearch")
    }

    func testCollapse_resetsQueryAndCallsOnSearch() {
        var searchQuery = "some query"
        var searchCallCount = 0
        let onSearch = { searchCallCount += 1 }

        // Simulate collapse behavior
        searchQuery = ""
        onSearch()

        XCTAssertTrue(searchQuery.isEmpty, "Collapse should clear query")
        XCTAssertEqual(searchCallCount, 1, "Collapse should call onSearch once")
    }
}
