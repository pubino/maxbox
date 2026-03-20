import XCTest
@testable import MaxBox

@MainActor
final class ComposeViewModelTests: XCTestCase {
    var mockGmail: MockGmailAPIService!
    var sut: ComposeViewModel!

    override func setUp() {
        super.setUp()
        mockGmail = MockGmailAPIService()
        sut = ComposeViewModel(gmailService: mockGmail)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(sut.to, "")
        XCTAssertEqual(sut.cc, "")
        XCTAssertEqual(sut.subject, "")
        XCTAssertEqual(sut.body, "")
        XCTAssertFalse(sut.isSending)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.didSend)
    }

    // MARK: - Validation

    func testIsValid_emptyFields_returnsFalse() {
        XCTAssertFalse(sut.isValid)
    }

    func testIsValid_onlyTo_returnsFalse() {
        sut.to = "alice@example.com"
        XCTAssertFalse(sut.isValid)
    }

    func testIsValid_onlySubject_returnsFalse() {
        sut.subject = "Test"
        XCTAssertFalse(sut.isValid)
    }

    func testIsValid_toAndSubject_returnsTrue() {
        sut.to = "alice@example.com"
        sut.subject = "Test Subject"
        XCTAssertTrue(sut.isValid)
    }

    func testIsValid_whitespaceOnly_returnsFalse() {
        sut.to = "   "
        sut.subject = "   "
        XCTAssertFalse(sut.isValid)
    }

    // MARK: - Send

    func testSend_success() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"
        sut.body = "Test body"
        sut.cc = "bob@example.com"

        await sut.send(accessToken: "token")

        XCTAssertTrue(sut.didSend)
        XCTAssertFalse(sut.isSending)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(mockGmail.sendMessageCallCount, 1)
        XCTAssertEqual(mockGmail.lastSendTo, "alice@example.com")
        XCTAssertEqual(mockGmail.lastSendSubject, "Hello")
        XCTAssertEqual(mockGmail.lastSendBody, "Test body")
        XCTAssertEqual(mockGmail.lastSendCc, "bob@example.com")
    }

    func testSend_emptyCc_sendsNil() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"

        await sut.send(accessToken: "token")

        XCTAssertTrue(sut.didSend)
        XCTAssertNil(mockGmail.lastSendCc)
    }

    func testSend_invalidForm_setsError() async {
        // to and subject are empty
        await sut.send(accessToken: "token")

        XCTAssertFalse(sut.didSend)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(mockGmail.sendMessageCallCount, 0)
    }

    func testSend_apiFailure() async {
        sut.to = "alice@example.com"
        sut.subject = "Hello"
        mockGmail.sendMessageError = GmailAPIError.requestFailed(500, "Server Error")

        await sut.send(accessToken: "token")

        XCTAssertFalse(sut.didSend)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.isSending)
    }

    // MARK: - Reset

    func testReset() {
        sut.to = "alice@example.com"
        sut.cc = "bob@example.com"
        sut.subject = "Hello"
        sut.body = "World"
        sut.errorMessage = "Some error"
        sut.didSend = true

        sut.reset()

        XCTAssertEqual(sut.to, "")
        XCTAssertEqual(sut.cc, "")
        XCTAssertEqual(sut.subject, "")
        XCTAssertEqual(sut.body, "")
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.didSend)
    }
}
