import XCTest
@testable import MaxBox

@MainActor
final class MailboxViewModelTests: XCTestCase {
    var mockAuth: MockAuthenticationService!
    var mockGmail: MockGmailAPIService!
    var mockPersistence: MockPersistenceService!
    var mockKeychain: MockKeychainService!
    var sut: MailboxViewModel!

    override func setUp() {
        super.setUp()
        mockAuth = MockAuthenticationService()
        mockGmail = MockGmailAPIService()
        mockPersistence = MockPersistenceService()
        mockKeychain = MockKeychainService()
        sut = MailboxViewModel(
            authService: mockAuth,
            gmailService: mockGmail,
            persistenceService: mockPersistence,
            keychainService: mockKeychain,
            skipRestore: true
        )
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(sut.accounts.isEmpty)
        XCTAssertEqual(sut.selectedMailboxType, .inbox)
        XCTAssertNil(sut.selectedAccountId)
        XCTAssertFalse(sut.isSigningIn)
        XCTAssertNil(sut.authError)
        XCTAssertEqual(sut.selection, .allAccounts(.inbox))
    }

    // MARK: - SidebarSelection

    func testSidebarSelection_allAccounts() {
        sut.selection = .allAccounts(.sent)
        XCTAssertEqual(sut.selectedMailboxType, .sent)
        XCTAssertNil(sut.selectedAccountId)
    }

    func testSidebarSelection_specificAccount() {
        sut.selection = .account(.inbox, accountId: "acc-1")
        XCTAssertEqual(sut.selectedMailboxType, .inbox)
        XCTAssertEqual(sut.selectedAccountId, "acc-1")
    }

    // MARK: - isMultiAccount

    func testIsMultiAccount_singleAccount() {
        sut.accounts = [Account.testAccount]
        XCTAssertFalse(sut.isMultiAccount)
    }

    func testIsMultiAccount_twoAccounts() {
        sut.accounts = [Account.testAccount, Account.testAccount2]
        XCTAssertTrue(sut.isMultiAccount)
    }

    func testIsMultiAccount_oneAuthenticatedOneNot() {
        sut.accounts = [Account.testAccount, Account.noTokenAccount]
        XCTAssertFalse(sut.isMultiAccount)
    }

    // MARK: - Mailboxes

    func testMailboxes_unified() {
        sut.selection = .allAccounts(.inbox)
        let mailboxes = sut.mailboxes
        XCTAssertEqual(mailboxes.count, MailboxType.allCases.count)
        XCTAssertTrue(mailboxes.allSatisfy { $0.accountId == "unified" })
    }

    func testMailboxes_specificAccount() {
        sut.selection = .account(.inbox, accountId: "acc-1")
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

    // MARK: - Active Accounts respects isActive

    func testActiveAccounts_filtersInactive() {
        sut.accounts = [Account.testAccount, Account.inactiveAccount]
        XCTAssertEqual(sut.activeAccounts.count, 1)
        XCTAssertEqual(sut.activeAccounts.first?.id, Account.testAccount.id)
    }

    func testIsMultiAccount_oneActive_oneInactive() {
        sut.accounts = [Account.testAccount, Account.inactiveAccount]
        XCTAssertFalse(sut.isMultiAccount)
    }

    // MARK: - Toggle Account Active

    func testToggleAccountActive() {
        sut.accounts = [Account.testAccount]
        XCTAssertTrue(sut.accounts[0].isActive)

        sut.toggleAccountActive(Account.testAccount)

        XCTAssertFalse(sut.accounts[0].isActive)
        XCTAssertTrue(sut.activeAccounts.isEmpty)
    }

    func testToggleAccountActive_reactivate() {
        sut.accounts = [Account.inactiveAccount]
        XCTAssertTrue(sut.activeAccounts.isEmpty)

        sut.toggleAccountActive(Account.inactiveAccount)

        XCTAssertTrue(sut.accounts[0].isActive)
        XCTAssertEqual(sut.activeAccounts.count, 1)
    }

    // MARK: - Cancel Sign In

    func testCancelSignIn_resetsState() {
        sut.isSigningIn = true
        sut.authError = "some error"

        sut.cancelSignIn()

        XCTAssertFalse(sut.isSigningIn)
        XCTAssertNil(sut.authError)
    }

    // MARK: - Account Email Lookup

    func testAccountEmail_found() {
        sut.accounts = [Account.testAccount]
        XCTAssertEqual(sut.accountEmail(for: "test-123"), "test@gmail.com")
    }

    func testAccountEmail_notFound() {
        sut.accounts = [Account.testAccount]
        XCTAssertNil(sut.accountEmail(for: "nonexistent"))
    }

    // MARK: - Persistence: Auto-save

    func testAccountsDidSet_persistsAccounts() {
        sut.accounts = [Account.testAccount]

        XCTAssertEqual(mockPersistence.saveAccountsCallCount, 1)
        XCTAssertEqual(mockPersistence.savedAccounts?.count, 1)
        XCTAssertEqual(mockPersistence.savedAccounts?.first?.id, Account.testAccount.id)
    }

    func testSelectionDidSet_persistsSelection() {
        sut.selection = .allAccounts(.sent)

        XCTAssertEqual(mockPersistence.saveSelectionCallCount, 1)
        XCTAssertEqual(mockPersistence.savedSelection, .allAccounts(.sent))
    }

    func testAccountsDidSet_excludesTokens() {
        sut.accounts = [Account.testAccount]

        let persisted = mockPersistence.savedAccounts?.first
        XCTAssertNotNil(persisted)
        // PersistableAccount does not store tokens
        let restored = persisted?.toAccount(accessToken: nil, refreshToken: nil)
        XCTAssertNil(restored?.accessToken)
        XCTAssertNil(restored?.refreshToken)
    }

    // MARK: - Persistence: Restore

    func testRestoreState_loadsAccountsFromDisk() {
        let pa = PersistableAccount(from: Account.testAccount)
        mockPersistence.loadAccountsResult = .success([pa])
        mockKeychain.storage["access_token_\(pa.id)"] = "restored-access"
        mockKeychain.storage["refresh_token_\(pa.id)"] = "restored-refresh"

        sut.restoreState()

        XCTAssertEqual(sut.accounts.count, 1)
        XCTAssertEqual(sut.accounts[0].id, pa.id)
        XCTAssertEqual(sut.accounts[0].accessToken, "restored-access")
        XCTAssertEqual(sut.accounts[0].refreshToken, "restored-refresh")
    }

    func testRestoreState_loadsSelection() {
        mockPersistence.loadSelectionResult = .success(.allAccounts(.sent))

        sut.restoreState()

        XCTAssertEqual(sut.selection, .allAccounts(.sent))
    }

    func testRestoreState_ignoresInvalidAccountSelection() {
        // Selection refers to an account that doesn't exist
        mockPersistence.loadSelectionResult = .success(.account(.inbox, accountId: "nonexistent"))

        sut.restoreState()

        // Should keep default selection
        XCTAssertEqual(sut.selection, .allAccounts(.inbox))
    }

    func testRestoreState_doesNotPersistDuringRestore() {
        let pa = PersistableAccount(from: Account.testAccount)
        mockPersistence.loadAccountsResult = .success([pa])
        mockPersistence.loadSelectionResult = .success(.allAccounts(.starred))

        sut.restoreState()

        // The didSet observers should not have fired during restore
        XCTAssertEqual(mockPersistence.saveAccountsCallCount, 0)
        XCTAssertEqual(mockPersistence.saveSelectionCallCount, 0)
    }

    // MARK: - Persistence: Cleanup on remove

    func testRemoveAccount_cleansCaches() async {
        sut.accounts = [Account.testAccount]
        mockPersistence.saveAccountsCallCount = 0 // reset from the append above

        await sut.removeAccount(Account.testAccount)

        // Should have called deleteMailboxCache for each MailboxType (account + allAccounts)
        XCTAssertEqual(mockPersistence.deleteCacheCallCount, MailboxType.allCases.count * 2)
    }
}
