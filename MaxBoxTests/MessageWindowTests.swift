import XCTest
@testable import MaxBox

@MainActor
final class MessageWindowTests: XCTestCase {

    // MARK: - MessageWindowContext

    func testContextIsHashable() {
        let ctx1 = MessageWindowContext(messageId: "msg-001", accountId: "acc-1")
        let ctx2 = MessageWindowContext(messageId: "msg-001", accountId: "acc-1")
        let ctx3 = MessageWindowContext(messageId: "msg-002", accountId: "acc-1")

        XCTAssertEqual(ctx1, ctx2)
        XCTAssertNotEqual(ctx1, ctx3)
    }

    func testContextIsCodable() throws {
        let original = MessageWindowContext(messageId: "msg-001", accountId: "acc-1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageWindowContext.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.messageId, "msg-001")
        XCTAssertEqual(decoded.accountId, "acc-1")
    }

    func testContextDifferentAccountIds() {
        let ctx1 = MessageWindowContext(messageId: "msg-001", accountId: "acc-1")
        let ctx2 = MessageWindowContext(messageId: "msg-001", accountId: "acc-2")

        XCTAssertNotEqual(ctx1, ctx2)
    }

    func testContextAsSetKey() {
        let ctx1 = MessageWindowContext(messageId: "msg-001", accountId: "acc-1")
        let ctx2 = MessageWindowContext(messageId: "msg-001", accountId: "acc-1")
        let ctx3 = MessageWindowContext(messageId: "msg-002", accountId: "acc-1")

        var set: Set<MessageWindowContext> = [ctx1, ctx2, ctx3]
        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(ctx1))
        XCTAssertTrue(set.contains(ctx3))
    }

    // MARK: - MessageDetailViewModel in Message Window Context

    func testViewModelLoadsMessageForWindow() async {
        let mockGmail = MockGmailAPIService()
        let testMsg = Message(
            id: "msg-win-001",
            threadId: "thread-001",
            subject: "Window Test",
            from: "sender@example.com",
            to: ["me@example.com"],
            cc: [],
            date: Date(),
            snippet: "Test snippet",
            body: "Test body",
            isRead: true,
            isStarred: false,
            labelIds: ["INBOX"]
        )
        mockGmail.getMessageResult = .success(testMsg)
        let vm = MessageDetailViewModel(gmailService: mockGmail)

        await vm.loadMessage(accessToken: "token", messageId: "msg-win-001")

        XCTAssertNotNil(vm.message)
        XCTAssertEqual(vm.message?.id, "msg-win-001")
        XCTAssertFalse(vm.isLoading)
    }

    func testArchiveFromWindowDismisses() async {
        let mockGmail = MockGmailAPIService()
        let vm = MessageDetailViewModel(gmailService: mockGmail)
        vm.message = Message.testMessage

        let result = await vm.archiveMessage(accessToken: "token")

        XCTAssertTrue(result, "Archive should succeed so window can dismiss")
        XCTAssertEqual(mockGmail.archiveMessageCallCount, 1)
    }

    func testTrashFromWindowDismisses() async {
        let mockGmail = MockGmailAPIService()
        let vm = MessageDetailViewModel(gmailService: mockGmail)
        vm.message = Message.testMessage

        let result = await vm.trashMessage(accessToken: "token")

        XCTAssertTrue(result, "Trash should succeed so window can dismiss")
        XCTAssertEqual(mockGmail.trashMessageCallCount, 1)
    }
}
