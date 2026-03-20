import XCTest
@testable import MaxBox

@MainActor
final class MessageDetailViewModelTests: XCTestCase {
    var mockGmail: MockGmailAPIService!
    var sut: MessageDetailViewModel!

    override func setUp() {
        super.setUp()
        mockGmail = MockGmailAPIService()
        sut = MessageDetailViewModel(gmailService: mockGmail)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertNil(sut.message)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Load Message

    func testLoadMessage_success() async {
        mockGmail.getMessageResult = .success(Message.testMessage)

        await sut.loadMessage(accessToken: "token", messageId: "msg-001")

        XCTAssertNotNil(sut.message)
        XCTAssertEqual(sut.message?.id, "msg-001")
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadMessage_failure() async {
        mockGmail.getMessageResult = .failure(GmailAPIError.requestFailed(404, "Not Found"))

        await sut.loadMessage(accessToken: "token", messageId: "msg-001")

        XCTAssertNil(sut.message)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Archive Message

    func testArchiveMessage_success() async {
        sut.message = Message.testMessage

        let result = await sut.archiveMessage(accessToken: "token")

        XCTAssertTrue(result)
        XCTAssertEqual(mockGmail.archiveMessageCallCount, 1)
        XCTAssertEqual(mockGmail.lastArchiveMessageId, "msg-001")
        XCTAssertNil(sut.errorMessage)
    }

    func testArchiveMessage_failure() async {
        sut.message = Message.testMessage
        mockGmail.archiveMessageError = GmailAPIError.requestFailed(500, "Server Error")

        let result = await sut.archiveMessage(accessToken: "token")

        XCTAssertFalse(result)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testArchiveMessage_noMessage_returnsFalse() async {
        sut.message = nil

        let result = await sut.archiveMessage(accessToken: "token")

        XCTAssertFalse(result)
        XCTAssertEqual(mockGmail.archiveMessageCallCount, 0)
    }

    // MARK: - Trash Message

    func testTrashMessage_success() async {
        sut.message = Message.testMessage

        let result = await sut.trashMessage(accessToken: "token")

        XCTAssertTrue(result)
        XCTAssertEqual(mockGmail.trashMessageCallCount, 1)
        XCTAssertEqual(mockGmail.lastTrashMessageId, "msg-001")
    }

    func testTrashMessage_failure() async {
        sut.message = Message.testMessage
        mockGmail.trashMessageError = GmailAPIError.notAuthenticated

        let result = await sut.trashMessage(accessToken: "token")

        XCTAssertFalse(result)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testTrashMessage_noMessage_returnsFalse() async {
        sut.message = nil

        let result = await sut.trashMessage(accessToken: "token")

        XCTAssertFalse(result)
        XCTAssertEqual(mockGmail.trashMessageCallCount, 0)
    }
}
