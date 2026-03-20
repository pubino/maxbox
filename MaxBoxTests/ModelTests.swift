import XCTest
@testable import MaxBox

final class AccountTests: XCTestCase {

    func testIsAuthenticated_withTokens_returnsTrue() {
        let account = Account.testAccount
        XCTAssertTrue(account.isAuthenticated)
    }

    func testIsAuthenticated_withoutTokens_returnsFalse() {
        let account = Account.noTokenAccount
        XCTAssertFalse(account.isAuthenticated)
    }

    func testIsTokenExpired_withFutureExpiry_returnsFalse() {
        let account = Account.testAccount
        XCTAssertFalse(account.isTokenExpired)
    }

    func testIsTokenExpired_withPastExpiry_returnsTrue() {
        let account = Account.expiredAccount
        XCTAssertTrue(account.isTokenExpired)
    }

    func testIsTokenExpired_withNilExpiry_returnsTrue() {
        let account = Account.noTokenAccount
        XCTAssertTrue(account.isTokenExpired)
    }

    func testAccountCodable() throws {
        let account = Account.testAccount
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertEqual(decoded.id, account.id)
        XCTAssertEqual(decoded.email, account.email)
        XCTAssertEqual(decoded.displayName, account.displayName)
        XCTAssertEqual(decoded.accessToken, account.accessToken)
        XCTAssertEqual(decoded.refreshToken, account.refreshToken)
    }
}

final class MailboxTypeTests: XCTestCase {

    func testAllCases() {
        XCTAssertEqual(MailboxType.allCases.count, 7)
    }

    func testDisplayNames() {
        XCTAssertEqual(MailboxType.inbox.displayName, "Inbox")
        XCTAssertEqual(MailboxType.starred.displayName, "Starred")
        XCTAssertEqual(MailboxType.drafts.displayName, "Drafts")
        XCTAssertEqual(MailboxType.sent.displayName, "Sent")
        XCTAssertEqual(MailboxType.allMail.displayName, "All Mail")
        XCTAssertEqual(MailboxType.spam.displayName, "Spam")
        XCTAssertEqual(MailboxType.trash.displayName, "Trash")
    }

    func testSystemImages() {
        XCTAssertEqual(MailboxType.inbox.systemImage, "tray.fill")
        XCTAssertEqual(MailboxType.starred.systemImage, "star.fill")
        XCTAssertEqual(MailboxType.trash.systemImage, "trash.fill")
    }

    func testGmailLabelIds() {
        XCTAssertEqual(MailboxType.inbox.gmailLabelId, "INBOX")
        XCTAssertEqual(MailboxType.starred.gmailLabelId, "STARRED")
        XCTAssertEqual(MailboxType.drafts.gmailLabelId, "DRAFT")
        XCTAssertEqual(MailboxType.sent.gmailLabelId, "SENT")
        XCTAssertEqual(MailboxType.allMail.gmailLabelId, "")
        XCTAssertEqual(MailboxType.spam.gmailLabelId, "SPAM")
        XCTAssertEqual(MailboxType.trash.gmailLabelId, "TRASH")
    }

    func testRawValues() {
        XCTAssertEqual(MailboxType.inbox.rawValue, "INBOX")
        XCTAssertEqual(MailboxType.allMail.rawValue, "ALL_MAIL")
    }
}

final class MailboxTests: XCTestCase {

    func testMailboxId() {
        let mailbox = Mailbox(type: .inbox, accountId: "acc-1")
        XCTAssertEqual(mailbox.id, "acc-1_INBOX")
    }

    func testMailboxDefaultUnreadCount() {
        let mailbox = Mailbox(type: .inbox, accountId: "acc-1")
        XCTAssertEqual(mailbox.unreadCount, 0)
    }

    func testMailboxCustomUnreadCount() {
        let mailbox = Mailbox(type: .inbox, accountId: "acc-1", unreadCount: 42)
        XCTAssertEqual(mailbox.unreadCount, 42)
    }
}

final class MessageTests: XCTestCase {

    func testFromDisplay_withAngleBrackets() {
        let msg = Message.testMessage
        XCTAssertEqual(msg.fromDisplay, "Alice Smith")
    }

    func testFromDisplay_withoutAngleBrackets() {
        var msg = Message.testMessage
        msg.from = "plain@example.com"
        XCTAssertEqual(msg.fromDisplay, "plain@example.com")
    }

    func testDateDisplay_today() {
        var msg = Message.testMessage
        msg.date = Date()
        let display = msg.dateDisplay
        // Today's date should show time format (h:mm a)
        XCTAssertTrue(display.contains(":") || display.contains("AM") || display.contains("PM"),
                       "Today's date should show time format, got: \(display)")
    }

    func testDateDisplay_yesterday() {
        var msg = Message.testMessage
        msg.date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(msg.dateDisplay, "Yesterday")
    }

    func testDateDisplay_olderDate() {
        var msg = Message.testMessage
        msg.date = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let display = msg.dateDisplay
        // Should show "MMM d" format
        XCTAssertFalse(display.isEmpty)
        XCTAssertNotEqual(display, "Yesterday")
    }

    func testPlaceholder() {
        let placeholder = Message.placeholder
        XCTAssertEqual(placeholder.id, "")
        XCTAssertEqual(placeholder.subject, "")
        XCTAssertTrue(placeholder.isRead)
        XCTAssertFalse(placeholder.isStarred)
    }
}

final class MessageListResponseTests: XCTestCase {

    func testDecodable() throws {
        let json = """
        {
            "messages": [{"id": "msg1", "threadId": "t1"}, {"id": "msg2", "threadId": "t2"}],
            "nextPageToken": "token123",
            "resultSizeEstimate": 42
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MessageListResponse.self, from: json)
        XCTAssertEqual(response.messages?.count, 2)
        XCTAssertEqual(response.messages?.first?.id, "msg1")
        XCTAssertEqual(response.nextPageToken, "token123")
        XCTAssertEqual(response.resultSizeEstimate, 42)
    }

    func testDecodable_emptyMessages() throws {
        let json = """
        {
            "resultSizeEstimate": 0
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MessageListResponse.self, from: json)
        XCTAssertNil(response.messages)
        XCTAssertNil(response.nextPageToken)
    }
}
