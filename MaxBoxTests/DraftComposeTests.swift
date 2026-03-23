import XCTest
@testable import MaxBox

@MainActor
final class DraftComposeTests: XCTestCase {

    // MARK: - DraftComposeContext

    func testContextIsHashable() {
        let ctx1 = DraftComposeContext(messageId: "msg-001", accountId: "acc-1")
        let ctx2 = DraftComposeContext(messageId: "msg-001", accountId: "acc-1")
        let ctx3 = DraftComposeContext(messageId: "msg-002", accountId: "acc-1")

        XCTAssertEqual(ctx1, ctx2)
        XCTAssertNotEqual(ctx1, ctx3)
    }

    func testContextIsCodable() throws {
        let original = DraftComposeContext(messageId: "draft-msg-001", accountId: "acc-1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DraftComposeContext.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.messageId, "draft-msg-001")
        XCTAssertEqual(decoded.accountId, "acc-1")
    }

    func testContextDifferentAccountIds() {
        let ctx1 = DraftComposeContext(messageId: "msg-001", accountId: "acc-1")
        let ctx2 = DraftComposeContext(messageId: "msg-001", accountId: "acc-2")

        XCTAssertNotEqual(ctx1, ctx2)
    }

    // MARK: - Message.isDraft

    func testIsDraft_withDraftLabel() {
        XCTAssertTrue(Message.draftMessage.isDraft)
    }

    func testIsDraft_withoutDraftLabel() {
        XCTAssertFalse(Message.testMessage.isDraft)
    }

    func testIsDraft_readMessage() {
        XCTAssertFalse(Message.readMessage.isDraft)
    }

    // MARK: - ComposeViewModel.loadDraft

    func testLoadDraft_populatesFields() async {
        let mockGmail = MockGmailAPIService()
        mockGmail.getMessageResult = .success(Message.draftMessage)
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "draft-msg-001")

        XCTAssertEqual(sut.to, "recipient@example.com")
        XCTAssertEqual(sut.cc, "cc@example.com")
        XCTAssertEqual(sut.subject, "Draft Subject")
        XCTAssertEqual(sut.body, "This is the draft body.")
        XCTAssertEqual(sut.draftId, "mock-draft-id")
        XCTAssertFalse(sut.isDirty)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadDraft_multipleTo() async {
        let mockGmail = MockGmailAPIService()
        let multiToMsg = Message(
            id: "draft-multi",
            threadId: "thread-m",
            subject: "Multi To",
            from: "me@gmail.com",
            to: ["a@example.com", "b@example.com"],
            cc: [],
            date: Date(),
            snippet: "",
            body: "Body",
            isRead: true,
            isStarred: false,
            labelIds: ["DRAFT"]
        )
        mockGmail.getMessageResult = .success(multiToMsg)
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "draft-multi")

        XCTAssertEqual(sut.to, "a@example.com, b@example.com")
        XCTAssertEqual(sut.cc, "")
    }

    func testLoadDraft_setsDraftIdFromApi() async {
        let mockGmail = MockGmailAPIService()
        mockGmail.getMessageResult = .success(Message.draftMessage)
        mockGmail.getDraftIdResult = "real-draft-id-123"
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "draft-msg-001")

        XCTAssertEqual(sut.draftId, "real-draft-id-123")
        XCTAssertEqual(mockGmail.getDraftIdCallCount, 1)
        XCTAssertEqual(mockGmail.lastGetDraftIdMessageId, "draft-msg-001")
    }

    func testLoadDraft_getDraftIdFails_stillLoadsFields() async {
        let mockGmail = MockGmailAPIService()
        mockGmail.getMessageResult = .success(Message.draftMessage)
        mockGmail.getDraftIdError = GmailAPIError.requestFailed(500, "Server Error")
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "draft-msg-001")

        // Fields should still be populated, draftId will be nil
        XCTAssertEqual(sut.to, "recipient@example.com")
        XCTAssertEqual(sut.subject, "Draft Subject")
        XCTAssertNil(sut.draftId)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadDraft_getMessageFails_setsError() async {
        let mockGmail = MockGmailAPIService()
        mockGmail.getMessageResult = .failure(GmailAPIError.requestFailed(404, "Not Found"))
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "nonexistent")

        XCTAssertEqual(sut.to, "")
        XCTAssertEqual(sut.subject, "")
        XCTAssertNotNil(sut.errorMessage)
    }

    func testLoadDraft_doesNotMarkDirty() async {
        let mockGmail = MockGmailAPIService()
        mockGmail.getMessageResult = .success(Message.draftMessage)
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "draft-msg-001")

        XCTAssertFalse(sut.isDirty, "Loading a draft should not mark it as dirty")
    }

    func testLoadDraft_thenEdit_marksDirty() async {
        let mockGmail = MockGmailAPIService()
        mockGmail.getMessageResult = .success(Message.draftMessage)
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "draft-msg-001")
        XCTAssertFalse(sut.isDirty)

        sut.body = "Modified body"
        XCTAssertTrue(sut.isDirty)
    }

    func testLoadDraft_thenSave_updatesDraft() async {
        let mockGmail = MockGmailAPIService()
        mockGmail.getMessageResult = .success(Message.draftMessage)
        mockGmail.getDraftIdResult = "existing-draft-id"
        let sut = ComposeViewModel(gmailService: mockGmail)

        await sut.loadDraft(accessToken: "token", messageId: "draft-msg-001")
        sut.accessToken = "token"
        sut.body = "Updated body"
        await sut.saveDraft()

        // Should UPDATE existing draft, not create new
        XCTAssertEqual(mockGmail.updateDraftCallCount, 1)
        XCTAssertEqual(mockGmail.createDraftCallCount, 0)
        XCTAssertEqual(mockGmail.lastDraftId, "existing-draft-id")
    }
}
