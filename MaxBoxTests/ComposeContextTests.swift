import XCTest
@testable import MaxBox

final class ComposeContextTests: XCTestCase {

    // MARK: - ComposeContext Model

    func testComposeContextCodable() throws {
        let ctx = ComposeContext(
            mode: .reply,
            accountId: "acc-1",
            originalFrom: "Alice <alice@example.com>",
            originalTo: ["bob@example.com"],
            originalCc: ["charlie@example.com"],
            originalSubject: "Hello",
            originalDate: Date(timeIntervalSince1970: 1700000000),
            originalBody: "Original body text",
            originalBodyHTML: "<p>Original body text</p>"
        )

        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(ComposeContext.self, from: data)

        XCTAssertEqual(decoded.mode, .reply)
        XCTAssertEqual(decoded.accountId, "acc-1")
        XCTAssertEqual(decoded.originalFrom, "Alice <alice@example.com>")
        XCTAssertEqual(decoded.originalTo, ["bob@example.com"])
        XCTAssertEqual(decoded.originalCc, ["charlie@example.com"])
        XCTAssertEqual(decoded.originalSubject, "Hello")
        XCTAssertEqual(decoded.originalBody, "Original body text")
        XCTAssertEqual(decoded.originalBodyHTML, "<p>Original body text</p>")
    }

    func testComposeContextHashable() {
        let ctx1 = ComposeContext(
            mode: .reply,
            accountId: "acc-1",
            originalFrom: "Alice <alice@example.com>",
            originalTo: ["bob@example.com"],
            originalCc: [],
            originalSubject: "Hello",
            originalDate: Date(timeIntervalSince1970: 1700000000),
            originalBody: "body",
            originalBodyHTML: nil
        )
        let ctx2 = ComposeContext(
            mode: .forward,
            accountId: "acc-1",
            originalFrom: "Alice <alice@example.com>",
            originalTo: ["bob@example.com"],
            originalCc: [],
            originalSubject: "Hello",
            originalDate: Date(timeIntervalSince1970: 1700000000),
            originalBody: "body",
            originalBodyHTML: nil
        )
        XCTAssertNotEqual(ctx1, ctx2)
    }

    func testComposeModeValues() {
        XCTAssertEqual(ComposeMode.reply.rawValue, "reply")
        XCTAssertEqual(ComposeMode.replyAll.rawValue, "replyAll")
        XCTAssertEqual(ComposeMode.forward.rawValue, "forward")
    }
}

@MainActor
final class PopulateFromContextTests: XCTestCase {
    var mockGmail: MockGmailAPIService!
    var sut: ComposeViewModel!

    override func setUp() {
        super.setUp()
        mockGmail = MockGmailAPIService()
        sut = ComposeViewModel(gmailService: mockGmail)
    }

    override func tearDown() {
        sut.stopAutoSave()
        super.tearDown()
    }

    // MARK: - Reply

    func testPopulateReply_setsToFromOriginalSender() {
        let ctx = makeContext(mode: .reply)
        sut.populateFromContext(ctx)

        XCTAssertEqual(sut.to, "Alice <alice@example.com>")
        XCTAssertEqual(sut.cc, "")
        XCTAssertEqual(sut.subject, "Re: Test Subject")
    }

    func testPopulateReply_preservesExistingRePrefix() {
        let ctx = makeContext(mode: .reply, subject: "Re: Already replied")
        sut.populateFromContext(ctx)

        XCTAssertEqual(sut.subject, "Re: Already replied")
    }

    // MARK: - Reply All

    func testPopulateReplyAll_setsToCcFromOriginalRecipients() {
        let ctx = makeContext(
            mode: .replyAll,
            to: ["me@example.com", "other@example.com"],
            cc: ["cc1@example.com"]
        )
        sut.populateFromContext(ctx)

        XCTAssertEqual(sut.to, "Alice <alice@example.com>")
        XCTAssertEqual(sut.cc, "me@example.com, other@example.com, cc1@example.com")
        XCTAssertEqual(sut.subject, "Re: Test Subject")
    }

    // MARK: - Forward

    func testPopulateForward_clearsToSetsFwdSubject() {
        let ctx = makeContext(mode: .forward)
        sut.populateFromContext(ctx)

        XCTAssertEqual(sut.to, "")
        XCTAssertEqual(sut.cc, "")
        XCTAssertEqual(sut.subject, "Fwd: Test Subject")
    }

    func testPopulateForward_preservesExistingFwdPrefix() {
        let ctx = makeContext(mode: .forward, subject: "Fwd: Already forwarded")
        sut.populateFromContext(ctx)

        XCTAssertEqual(sut.subject, "Fwd: Already forwarded")
    }

    // MARK: - Quoted Body

    func testPopulateReply_quotesPlainTextBody() {
        let ctx = makeContext(mode: .reply, body: "Line 1\nLine 2")
        sut.populateFromContext(ctx)

        XCTAssertTrue(sut.body.contains("> Line 1"))
        XCTAssertTrue(sut.body.contains("> Line 2"))
        XCTAssertTrue(sut.body.contains("wrote:"))
    }

    func testPopulateReply_quotesHTMLBody() {
        let ctx = makeContext(mode: .reply, body: "", bodyHTML: "<p>Hello</p><br><p>World</p>")
        sut.populateFromContext(ctx)

        XCTAssertTrue(sut.body.contains("> Hello"))
        XCTAssertTrue(sut.body.contains("wrote:"))
    }

    func testPopulateReply_doesNotMarkDirty() {
        let ctx = makeContext(mode: .reply)
        sut.populateFromContext(ctx)

        XCTAssertFalse(sut.isDirty)
    }

    // MARK: - Helpers

    private func makeContext(
        mode: ComposeMode,
        subject: String = "Test Subject",
        to: [String] = ["bob@example.com"],
        cc: [String] = [],
        body: String = "Original body",
        bodyHTML: String? = nil
    ) -> ComposeContext {
        ComposeContext(
            mode: mode,
            accountId: "acc-1",
            originalFrom: "Alice <alice@example.com>",
            originalTo: to,
            originalCc: cc,
            originalSubject: subject,
            originalDate: Date(timeIntervalSince1970: 1700000000),
            originalBody: body,
            originalBodyHTML: bodyHTML
        )
    }
}

// MARK: - Message.hasRemoteImages Tests

final class MessageRemoteImagesTests: XCTestCase {

    func testHasRemoteImages_noHTML_returnsFalse() {
        var msg = Message.testMessage
        msg.bodyHTML = nil
        XCTAssertFalse(msg.hasRemoteImages)
    }

    func testHasRemoteImages_emptyHTML_returnsFalse() {
        var msg = Message.testMessage
        msg.bodyHTML = ""
        XCTAssertFalse(msg.hasRemoteImages)
    }

    func testHasRemoteImages_noImages_returnsFalse() {
        var msg = Message.testMessage
        msg.bodyHTML = "<p>Just text</p>"
        XCTAssertFalse(msg.hasRemoteImages)
    }

    func testHasRemoteImages_withHttpImage_returnsTrue() {
        var msg = Message.testMessage
        msg.bodyHTML = """
        <p>Hello</p><img src="https://example.com/photo.jpg" alt="photo">
        """
        XCTAssertTrue(msg.hasRemoteImages)
    }

    func testHasRemoteImages_withHttpImageNoS_returnsTrue() {
        var msg = Message.testMessage
        msg.bodyHTML = """
        <p>Hello</p><img src="http://example.com/photo.jpg" alt="photo">
        """
        XCTAssertTrue(msg.hasRemoteImages)
    }

    func testHasRemoteImages_withDataImage_returnsFalse() {
        var msg = Message.testMessage
        msg.bodyHTML = """
        <img src="data:image/png;base64,iVBORw0KGgoAAAA">
        """
        XCTAssertFalse(msg.hasRemoteImages)
    }

    func testHasRemoteImages_withCidImage_returnsFalse() {
        var msg = Message.testMessage
        msg.bodyHTML = """
        <img src="cid:image001.png@01D12345.67890ABC">
        """
        XCTAssertFalse(msg.hasRemoteImages)
    }
}
