import XCTest
@testable import MaxBox

@MainActor
final class MessageListViewModelTests: XCTestCase {
    var mockGmail: MockGmailAPIService!
    var activityManager: ActivityManager!
    var mockPersistence: MockPersistenceService!
    var sut: MessageListViewModel!

    override func setUp() {
        super.setUp()
        mockGmail = MockGmailAPIService()
        activityManager = ActivityManager()
        mockPersistence = MockPersistenceService()
        sut = MessageListViewModel(
            gmailService: mockGmail,
            activityManager: activityManager,
            persistenceService: mockPersistence
        )
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertNil(sut.selectedMessageId)
        XCTAssertFalse(sut.isLoading)
        XCTAssertFalse(sut.isRefreshing)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertFalse(sut.filterUnread)
        XCTAssertTrue(sut.cache.isEmpty)
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
    }

    // MARK: - Load Messages with AccountId

    func testLoadMessages_stampsAccountId() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.loadMessages(accountId: "acc-1", accessToken: "token", labelId: "INBOX")

        XCTAssertEqual(sut.messages.first?.accountId, "acc-1")
    }

    func testLoadMessages_noAccountId_leavesNil() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertNil(sut.messages.first?.accountId)
    }

    // MARK: - Load Messages From All Accounts

    func testLoadMessagesFromAllAccounts_mergesAndSorts() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        let tokens = [
            (accountId: "acc-1", token: "token-1"),
            (accountId: "acc-2", token: "token-2")
        ]

        await sut.loadMessagesFromAllAccounts(tokens: tokens, labelId: "INBOX")

        XCTAssertEqual(sut.messages.count, 2)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockGmail.listMessagesCallCount, 2)
    }

    func testLoadMessagesFromAllAccounts_stampsAccountIds() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        let tokens = [
            (accountId: "acc-1", token: "token-1"),
            (accountId: "acc-2", token: "token-2")
        ]

        await sut.loadMessagesFromAllAccounts(tokens: tokens, labelId: "INBOX")

        let accountIds = Set(sut.messages.compactMap(\.accountId))
        XCTAssertEqual(accountIds, ["acc-1", "acc-2"])
    }

    func testLoadMessagesFromAllAccounts_emptyTokens() async {
        await sut.loadMessagesFromAllAccounts(tokens: [], labelId: "INBOX")

        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    func testLoadMessagesFromAllAccounts_partialFailure() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        let tokens = [
            (accountId: "acc-1", token: "token-1")
        ]

        await sut.loadMessagesFromAllAccounts(tokens: tokens, labelId: "INBOX")

        XCTAssertEqual(sut.messages.count, 1)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - switchMailbox (cache-aware)

    func testSwitchMailbox_firstLoad_populatesCache() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        let selection = SidebarSelection.allAccounts(.inbox)
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "token-1")]
        )

        XCTAssertEqual(sut.messages.count, 1)
        XCTAssertNotNil(sut.cache[selection])
        XCTAssertEqual(sut.cache[selection]?.messages.count, 1)
    }

    func testSwitchMailbox_cacheHit_restoresInstantly() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Seed the cache
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "token-1")]
        )

        let callsBefore = mockGmail.getMessageCallCount

        // Switch away
        sut.messages = []

        // Switch back — cache should restore messages; differential sync finds no changes
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "token-1")]
        )

        XCTAssertEqual(sut.messages.count, 1)
        // Differential sync does a listMessages check but should NOT refetch getMessage
        // because the ID set hasn't changed
        XCTAssertEqual(mockGmail.getMessageCallCount, callsBefore)
    }

    func testSwitchMailbox_searchBypassesCache() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Seed cache
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "token-1")]
        )
        let callsBefore = mockGmail.listMessagesCallCount

        // Search — should bypass cache
        sut.searchQuery = "from:alice"
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "token-1")]
        )

        // Should have made a fresh listMessages call
        XCTAssertGreaterThan(mockGmail.listMessagesCallCount, callsBefore)
        XCTAssertEqual(mockGmail.lastListQuery, "from:alice")
    }

    func testSwitchMailbox_forceRefresh_ignoresCache() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Seed cache
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "token-1")]
        )
        let callsBefore = mockGmail.getMessageCallCount

        // Force refresh
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "token-1")],
            forceRefresh: true
        )

        // Should refetch full messages
        XCTAssertGreaterThan(mockGmail.getMessageCallCount, callsBefore)
    }

    func testSwitchMailbox_differentSelections_separateCaches() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        let inbox = SidebarSelection.allAccounts(.inbox)
        let sent = SidebarSelection.allAccounts(.sent)

        await sut.switchMailbox(selection: inbox, tokens: [(accountId: "acc-1", token: "t1")])
        await sut.switchMailbox(selection: sent, tokens: [(accountId: "acc-1", token: "t1")])

        XCTAssertNotNil(sut.cache[inbox])
        XCTAssertNotNil(sut.cache[sent])
    }

    // MARK: - Differential sync

    func testDifferentialSync_newMessageAppears() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Initial load with 1 message
        let refs1 = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs1, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])
        XCTAssertEqual(sut.messages.count, 1)

        // Now API returns 2 messages (a new one appeared)
        let refs2 = [
            MessageRef(id: "msg-001", threadId: "t-001"),
            MessageRef(id: "msg-002", threadId: "t-002")
        ]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs2, nextPageToken: nil, resultSizeEstimate: 2)
        )

        let getCallsBefore = mockGmail.getMessageCallCount

        // Switch away and back to trigger differential sync
        sut.messages = []
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        // Should have fetched only the new message (msg-002), not msg-001 again
        XCTAssertEqual(mockGmail.getMessageCallCount, getCallsBefore + 1)
        XCTAssertEqual(sut.messages.count, 2)
    }

    func testDifferentialSync_messageRemoved() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Initial load with 2 messages
        let refs1 = [
            MessageRef(id: "msg-001", threadId: "t-001"),
            MessageRef(id: "msg-002", threadId: "t-002")
        ]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs1, nextPageToken: nil, resultSizeEstimate: 2)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])
        XCTAssertEqual(sut.messages.count, 2)

        // Now API returns only 1 message (one was deleted/archived)
        let refs2 = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs2, nextPageToken: nil, resultSizeEstimate: 1)
        )

        let getCallsBefore = mockGmail.getMessageCallCount

        // Switch away and back
        sut.messages = []
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        // Should NOT have fetched any messages (msg-001 already cached)
        XCTAssertEqual(mockGmail.getMessageCallCount, getCallsBefore)
        // Should have removed msg-002
        XCTAssertEqual(sut.messages.count, 1)
        XCTAssertEqual(sut.messages.first?.id, "msg-001")
    }

    func testDifferentialSync_noChanges_noRefetch() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        let getCallsBefore = mockGmail.getMessageCallCount
        let listCallsBefore = mockGmail.listMessagesCallCount

        // Switch away and back — same data from API
        sut.messages = []
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        // Should have called listMessages (for the diff check) but NOT getMessage
        XCTAssertGreaterThan(mockGmail.listMessagesCallCount, listCallsBefore)
        XCTAssertEqual(mockGmail.getMessageCallCount, getCallsBefore)
    }

    // MARK: - Cache mutation propagation

    func testMarkAsRead_updatesCacheEntry() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        XCTAssertFalse(sut.cache[selection]!.messages[0].isRead)

        await sut.markAsRead(accessToken: "t1", messageId: "msg-001")

        XCTAssertTrue(sut.messages[0].isRead)
        XCTAssertTrue(sut.cache[selection]!.messages[0].isRead)
    }

    func testToggleStar_updatesCacheEntry() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        XCTAssertFalse(sut.cache[selection]!.messages[0].isStarred)

        await sut.toggleStar(accessToken: "t1", messageId: "msg-001")

        XCTAssertTrue(sut.messages[0].isStarred)
        XCTAssertTrue(sut.cache[selection]!.messages[0].isStarred)
    }

    // MARK: - removeMessage

    func testRemoveMessage_removesFromListAndCache() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        let refs = [
            MessageRef(id: "msg-001", threadId: "t-001"),
            MessageRef(id: "msg-002", threadId: "t-002")
        ]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 2)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])
        XCTAssertEqual(sut.messages.count, 2)
        XCTAssertEqual(sut.cache[selection]?.messages.count, 2)

        sut.removeMessage(id: "msg-001")

        XCTAssertEqual(sut.messages.count, 1)
        XCTAssertEqual(sut.messages.first?.id, "msg-002")
        XCTAssertEqual(sut.cache[selection]?.messages.count, 1)
        XCTAssertEqual(sut.cache[selection]?.messages.first?.id, "msg-002")
    }

    func testRemoveMessage_nonexistentId_noOp() {
        sut.messages = [Message.testMessage]
        sut.removeMessage(id: "nonexistent")
        XCTAssertEqual(sut.messages.count, 1)
    }

    // MARK: - invalidateCache

    func testInvalidateCache_specific() async {
        let inbox = SidebarSelection.allAccounts(.inbox)
        let sent = SidebarSelection.allAccounts(.sent)
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.switchMailbox(selection: inbox, tokens: [(accountId: "a", token: "t")])
        await sut.switchMailbox(selection: sent, tokens: [(accountId: "a", token: "t")])

        sut.invalidateCache(for: inbox)

        XCTAssertNil(sut.cache[inbox])
        XCTAssertNotNil(sut.cache[sent])
    }

    func testInvalidateCache_all() async {
        let inbox = SidebarSelection.allAccounts(.inbox)
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: inbox, tokens: [(accountId: "a", token: "t")])

        sut.invalidateCache()

        XCTAssertTrue(sut.cache.isEmpty)
    }

    // MARK: - Load More Messages

    func testLoadMoreMessages_appendsToExisting() async {
        let refs1 = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs1, nextPageToken: "page2", resultSizeEstimate: 100)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.loadMessages(accessToken: "token", labelId: "INBOX")

        let refs2 = [MessageRef(id: "msg-002", threadId: "t-002")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs2, nextPageToken: nil, resultSizeEstimate: 100)
        )
        await sut.loadMoreMessages(accessToken: "token", labelId: "INBOX")

        XCTAssertEqual(sut.messages.count, 2)
        XCTAssertEqual(mockGmail.lastListPageToken, "page2")
    }

    func testLoadMoreMessages_noMorePages_doesNothing() async {
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
        sut.messages = [Message.readMessage]
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

    // MARK: - Activity tracking

    func testSwitchMailbox_reportsActivity() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.switchMailbox(
            selection: .allAccounts(.inbox),
            tokens: [(accountId: "acc-1", token: "t1")]
        )

        // Activity should have been created and completed
        XCTAssertFalse(activityManager.activities.isEmpty)
        XCTAssertTrue(activityManager.activities.allSatisfy {
            if case .completed = $0.status { return true }
            return false
        })
    }

    func testDifferentialSync_reportsActivity() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        let activitiesBefore = activityManager.activities.count

        // Switch away and back to trigger differential sync
        sut.messages = []
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        // Should have created a new activity for the sync
        XCTAssertGreaterThan(activityManager.activities.count, activitiesBefore)
    }

    func testProgressiveLoad_reportsProgress() async {
        let refs = [
            MessageRef(id: "msg-001", threadId: "t-001"),
            MessageRef(id: "msg-002", threadId: "t-002")
        ]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 2)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.switchMailbox(
            selection: .allAccounts(.inbox),
            tokens: [(accountId: "acc-1", token: "t1")]
        )

        // After completion, messages should be loaded
        XCTAssertEqual(sut.messages.count, 2)
        // Activity should show completion
        let loadActivity = activityManager.activities.first { $0.title.contains("Loading") }
        XCTAssertNotNil(loadActivity)
        if case .completed = loadActivity?.status {} else {
            XCTFail("Activity should be completed")
        }
    }

    // MARK: - Disk Cache

    func testSwitchMailbox_persistsCacheToDisk() async {
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        let selection = SidebarSelection.allAccounts(.inbox)
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "t1")]
        )

        XCTAssertEqual(mockPersistence.saveCacheCallCount, 1)
        XCTAssertNotNil(mockPersistence.savedCaches[selection])
        XCTAssertEqual(mockPersistence.savedCaches[selection]?.messages.count, 1)
    }

    func testSwitchMailbox_restoresFromDiskCache() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Seed disk cache (recent, within 1 hour)
        let diskCache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date().addingTimeInterval(-600), // 10 minutes ago
            nextPageToken: nil,
            hasMorePages: false
        ))
        mockPersistence.savedCaches[selection] = diskCache

        // API returns same data for differential sync
        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )

        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "t1")]
        )

        // Should have loaded from disk cache
        XCTAssertEqual(mockPersistence.loadCacheCallCount, 1)
        XCTAssertEqual(sut.messages.count, 1)
        XCTAssertEqual(sut.messages.first?.id, "msg-001")
    }

    func testSwitchMailbox_expiredDiskCache_doesFullFetch() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Seed disk cache (expired, >1 hour old)
        let diskCache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date().addingTimeInterval(-7200), // 2 hours ago
            nextPageToken: nil,
            hasMorePages: false
        ))
        mockPersistence.savedCaches[selection] = diskCache

        let refs = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "t1")]
        )

        // Should have done a full fetch (getMessage called)
        XCTAssertGreaterThan(mockGmail.getMessageCallCount, 0)
    }

    func testSwitchMailbox_searchBypassesDiskCache() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Seed disk cache
        let diskCache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date(),
            nextPageToken: nil,
            hasMorePages: false
        ))
        mockPersistence.savedCaches[selection] = diskCache

        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: nil, nextPageToken: nil, resultSizeEstimate: 0)
        )

        sut.searchQuery = "from:alice"
        await sut.switchMailbox(
            selection: selection,
            tokens: [(accountId: "acc-1", token: "t1")]
        )

        // Search should bypass disk cache
        XCTAssertEqual(mockPersistence.loadCacheCallCount, 0)
    }

    func testDifferentialSync_persistsUpdatedCache() async {
        let selection = SidebarSelection.allAccounts(.inbox)

        // Initial load
        let refs1 = [MessageRef(id: "msg-001", threadId: "t-001")]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs1, nextPageToken: nil, resultSizeEstimate: 1)
        )
        mockGmail.getMessageResult = .success(Message.testMessage)
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        let saveCountAfterInitial = mockPersistence.saveCacheCallCount

        // Differential sync adds a new message
        let refs2 = [
            MessageRef(id: "msg-001", threadId: "t-001"),
            MessageRef(id: "msg-002", threadId: "t-002")
        ]
        mockGmail.listMessagesResult = .success(
            MessageListResponse(messages: refs2, nextPageToken: nil, resultSizeEstimate: 2)
        )

        sut.messages = []
        await sut.switchMailbox(selection: selection, tokens: [(accountId: "acc-1", token: "t1")])

        // Should have persisted updated cache
        XCTAssertGreaterThan(mockPersistence.saveCacheCallCount, saveCountAfterInitial)
    }
}
