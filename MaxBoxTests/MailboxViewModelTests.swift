import XCTest
@testable import MaxBox

@MainActor
final class MailboxViewModelTests: XCTestCase {
    var mockAuth: MockAuthenticationService!
    var mockGmail: MockGmailAPIService!
    var sut: MailboxViewModel!

    override func setUp() {
        super.setUp()
        mockAuth = MockAuthenticationService()
        mockGmail = MockGmailAPIService()
        sut = MailboxViewModel(authService: mockAuth, gmailService: mockGmail)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(sut.accounts.isEmpty)
        XCTAssertEqual(sut.selectedMailboxType, .inbox)
        XCTAssertNil(sut.selectedAccountId)
        XCTAssertFalse(sut.isSigningIn)
        XCTAssertNil(sut.authError)
    }

    // MARK: - Mailboxes

    func testMailboxes_unified() {
        sut.selectedAccountId = nil
        let mailboxes = sut.mailboxes
        XCTAssertEqual(mailboxes.count, MailboxType.allCases.count)
        XCTAssertTrue(mailboxes.allSatisfy { $0.accountId == "unified" })
    }

    func testMailboxes_specificAccount() {
        sut.selectedAccountId = "acc-1"
        let mailboxes = sut.mailboxes
        XCTAssertEqual(mailboxes.count, MailboxType.allCases.count)
        XCTAssertTrue(mailboxes.allSatisfy { $0.accountId == "acc-1" })
    }

    // MARK: - Add Account

    func testAddAccount_success() async {
        let testAccount = Account.testAccount
        mockAuth.signInResult = .success(testAccount)

        await sut.addAccount()

        XCTAssertEqual(sut.accounts.count, 1)
        XCTAssertEqual(sut.accounts.first?.id, testAccount.id)
        XCTAssertFalse(sut.isSigningIn)
        XCTAssertNil(sut.authError)
        XCTAssertEqual(mockAuth.signInCallCount, 1)
    }

    func testAddAccount_failure() async {
        mockAuth.signInResult = .failure(AuthError.noClientId)

        await sut.addAccount()

        XCTAssertTrue(sut.accounts.isEmpty)
        XCTAssertFalse(sut.isSigningIn)
        XCTAssertNotNil(sut.authError)
    }

    func testAddAccount_duplicateUpdatesExisting() async {
        let account = Account.testAccount
        mockAuth.signInResult = .success(account)

        await sut.addAccount()
        await sut.addAccount()

        XCTAssertEqual(sut.accounts.count, 1)
        XCTAssertEqual(mockAuth.signInCallCount, 2)
    }

    // MARK: - Remove Account

    func testRemoveAccount() async {
        let account = Account.testAccount
        sut.accounts = [account]

        await sut.removeAccount(account)

        XCTAssertTrue(sut.accounts.isEmpty)
        XCTAssertEqual(mockAuth.signOutCallCount, 1)
        XCTAssertEqual(mockAuth.lastSignedOutAccount?.id, account.id)
    }

    func testRemoveAccount_signOutFails_stillRemovesLocally() async {
        let account = Account.testAccount
        sut.accounts = [account]
        mockAuth.signOutError = AuthError.notAuthenticated

        await sut.removeAccount(account)

        XCTAssertTrue(sut.accounts.isEmpty)
    }

    // MARK: - Access Token

    func testGetAccessToken_success() async throws {
        let account = Account.testAccount
        sut.accounts = [account]
        mockAuth.accessTokenResult = .success("valid-token")

        let token = try await sut.getAccessToken(for: account.id)
        XCTAssertEqual(token, "valid-token")
    }

    func testGetAccessToken_noAccount_throws() async {
        do {
            _ = try await sut.getAccessToken(for: "nonexistent")
            XCTFail("Should throw")
        } catch {
            XCTAssertTrue(error is AuthError)
        }
    }

    // MARK: - Active Accounts

    func testActiveAccounts_filtersUnauthenticated() {
        sut.accounts = [Account.testAccount, Account.noTokenAccount]
        XCTAssertEqual(sut.activeAccounts.count, 1)
        XCTAssertEqual(sut.activeAccounts.first?.id, Account.testAccount.id)
    }
}
