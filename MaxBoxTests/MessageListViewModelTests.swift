import XCTest
@testable import MaxBox

@MainActor
final class MessageListViewModelTests: XCTestCase {
    var mockGmail: MockGmailAPIService!
    var sut: MessageListViewModel!

    override func setUp() {
        super.setUp()
        mockGmail = MockGmailAPIService()
        sut = MessageListViewModel(gmailService: mockGmail)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertNil(sut.selectedMessageId)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertFalse(sut.filterUnread)
    }

    // MARK: - Load Messages

    func testLoadMessages_success() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertEqual(sut.messages.count, 1)
        XCTAssertEqual(sut.messages.first?.id, "msg-001")
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockGmail.lastListAccessToken, "token")
        XCTAssertEqual(mockGmail.lastListLabelId, "INBOX")
    }

    func testLoadMessages_emptyList() async {
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: nil, nextPageToken: nil, resultSizeEstimate: 0)
        )

        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadMessages_apiError() async {
        mockGmail.listMessagesResult = .failure(GmailAPIError.notAuthenticated)

        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadMessages_withPagination() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: "page2", resultSizeEstimate: 100)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertEqual(sut.messages.count, 1)
        // nextPageToken should be stored internally for loadMore
    }

    // MARK: - Load More Messages

    func testLoadMoreMessages_appendsToExisting() async {
        // First load
        let refs1 = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs1, nextPageToken: "page2", resultSizeEstimate: 100)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        // Second load (load more)
        let refs2 = [MessageRef(id: "msg-002", threadId: "t-002")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs2, nextPageToken: nil, resultSizeEstimate: 100)
        )
        await sut.loadMoreMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertEqual(sut.messages.count, 2)
        XCTAssertEqual(mockGmail.lastListPageToken, "page2")
    }

    func testLoadMoreMessages_noMorePages_doesNothing() async {
        // Load with no nextPageToken
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: nil, nextPageToken: nil, resultSizeEstimate: 0)
        )
        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        let callsBefore = mockGmail.listMessagesCallCount
        await sut.loadMoreMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertEqual(mockGmail.listMessagesCallCount, callsBefore)
    }

    // MARK: - Filter

    func testFilteredMessages_unreadOnly() {
        sut.messages = [Message.testMessage, Message.readMessage]

        sut.filterUnread = true
        XCTAssertEqual(sut.filteredMessages.count, 1)
        XCTAssertFalse(sut.filteredMessages.first!.isRead)

        sut.filterUnread = false
        XCTAssertEqual(sut.filteredMessages.count, 2)
    }

    // MARK: - Selected Message

    func testSelectedMessage() {
        sut.messages = [Message.testMessage, Message.readMessage]

        sut.selectedMessageId = "msg-001"
        XCTAssertEqual(sut.selectedMessage?.id, "msg-001")

        sut.selectedMessageId = "nonexistent"
        XCTAssertNil(sut.selectedMessage)
    }

    // MARK: - Mark as Read

    func testMarkAsRead_success() async {
        sut.messages = [Message.testMessage]
        XCTAssertFalse(sut.messages[0].isRead)

        await sut.markAsRead(accessToken: "token", messageId: "msg-001")

        XCTAssertTrue(sut.messages[0].isRead)
        XCTAssertEqual(mockGmail.modifyMessageCallCount, 1)
        XCTAssertEqual(mockGmail.lastModifyRemoveLabels, ["UNREAD"])
    }

    func testMarkAsRead_failure_setsError() async {
        sut.messages = [Message.testMessage]
        mockGmail.modifyMessageError = GmailAPIError.notAuthenticated

        await sut.markAsRead(accessToken: "token", messageId: "msg-001")

        XCTAssertFalse(sut.messages[0].isRead)
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - Toggle Star

    func testToggleStar_addStar() async {
        sut.messages = [Message.testMessage]
        XCTAssertFalse(sut.messages[0].isStarred)

        await sut.toggleStar(accessToken: "token", messageId: "msg-001")

        XCTAssertTrue(sut.messages[0].isStarred)
        XCTAssertEqual(mockGmail.lastModifyAddLabels, ["STARRED"])
        XCTAssertEqual(mockGmail.lastModifyRemoveLabels, [])
    }

    func testToggleStar_removeStar() async {
        sut.messages = [Message.readMessage]  // readMessage.isStarred == true
        XCTAssertTrue(sut.messages[0].isStarred)

        await sut.toggleStar(accessToken: "token", messageId: "msg-002")

        XCTAssertFalse(sut.messages[0].isStarred)
        XCTAssertEqual(mockGmail.lastModifyAddLabels, [])
        XCTAssertEqual(mockGmail.lastModifyRemoveLabels, ["STARRED"])
    }

    func testToggleStar_failure_setsError() async {
        sut.messages = [Message.testMessage]
        mockGmail.modifyMessageError = GmailAPIError.requestFailed(403, "Forbidden")

        await sut.toggleStar(accessToken: "token", messageId: "msg-001")

        XCTAssertFalse(sut.messages[0].isStarred)
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - Search Query

    func testLoadMessages_withSearchQuery() async {
        sut.searchQuery = "from:alice"
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: nil, nextPageToken: nil, resultSizeEstimate: 0)
        )

        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertEqual(mockGmail.lastListQuery, "from:alice")
    }
}
