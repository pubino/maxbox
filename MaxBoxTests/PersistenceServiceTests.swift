import XCTest
@testable import MaxBox

final class PersistenceServiceTests: XCTestCase {
    var sut: PersistenceService!
    var testDirectory: URL!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaxBoxPersistenceTests_\(UUID().uuidString)")
        testDefaults = UserDefaults(suiteName: "com.maxbox.tests.\(UUID().uuidString)")!
        sut = PersistenceService(
            fileManager: .default,
            defaults: testDefaults,
            baseDirectory: testDirectory
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        testDefaults.removePersistentDomain(forName: testDefaults.description)
        super.tearDown()
    }

    // MARK: - Accounts

    func testSaveAndLoadAccounts() throws {
        let accounts = [
            PersistableAccount(from: Account.testAccount),
            PersistableAccount(from: Account.testAccount2)
        ]

        try sut.saveAccounts(accounts)
        let loaded = try sut.loadAccounts()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, Account.testAccount.id)
        XCTAssertEqual(loaded[1].id, Account.testAccount2.id)
    }

    func testLoadAccounts_noFile_returnsEmpty() throws {
        let loaded = try sut.loadAccounts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDeleteAccounts() throws {
        let accounts = [PersistableAccount(from: Account.testAccount)]
        try sut.saveAccounts(accounts)
        try sut.deleteAccounts()

        let loaded = try sut.loadAccounts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveAccounts_excludesTokens() throws {
        let account = Account.testAccount
        let persisted = PersistableAccount(from: account)

        try sut.saveAccounts([persisted])
        let loaded = try sut.loadAccounts()

        let restored = loaded[0].toAccount(accessToken: nil, refreshToken: nil)
        XCTAssertNil(restored.accessToken)
        XCTAssertNil(restored.refreshToken)
        XCTAssertEqual(restored.email, account.email)
        XCTAssertEqual(restored.displayName, account.displayName)
    }

    func testSaveAccounts_preservesMetadata() throws {
        let account = Account.testAccount
        let persisted = PersistableAccount(from: account)

        try sut.saveAccounts([persisted])
        let loaded = try sut.loadAccounts()

        XCTAssertEqual(loaded[0].email, account.email)
        XCTAssertEqual(loaded[0].displayName, account.displayName)
        XCTAssertEqual(loaded[0].isActive, account.isActive)
    }

    func testSaveAccounts_overwritesPrevious() throws {
        try sut.saveAccounts([PersistableAccount(from: Account.testAccount)])
        try sut.saveAccounts([PersistableAccount(from: Account.testAccount2)])

        let loaded = try sut.loadAccounts()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, Account.testAccount2.id)
    }

    // MARK: - Selection

    func testSaveAndLoadSelection_allAccounts() throws {
        let selection = SidebarSelection.allAccounts(.sent)
        try sut.saveSelection(selection)

        let loaded = try sut.loadSelection()
        XCTAssertEqual(loaded, selection)
    }

    func testSaveAndLoadSelection_specificAccount() throws {
        let selection = SidebarSelection.account(.inbox, accountId: "acc-123")
        try sut.saveSelection(selection)

        let loaded = try sut.loadSelection()
        XCTAssertEqual(loaded, selection)
    }

    func testLoadSelection_noData_returnsNil() throws {
        let loaded = try sut.loadSelection()
        XCTAssertNil(loaded)
    }

    // MARK: - Mailbox Cache

    func testSaveAndLoadMailboxCache() throws {
        let selection = SidebarSelection.allAccounts(.inbox)
        let cache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date(),
            nextPageToken: "page2",
            hasMorePages: true
        ))

        try sut.saveMailboxCache(cache, for: selection)
        let loaded = try sut.loadMailboxCache(for: selection)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.messages.first?.id, Message.testMessage.id)
        XCTAssertEqual(loaded?.nextPageToken, "page2")
        XCTAssertTrue(loaded?.hasMorePages == true)
    }

    func testLoadMailboxCache_noFile_returnsNil() throws {
        let loaded = try sut.loadMailboxCache(for: .allAccounts(.inbox))
        XCTAssertNil(loaded)
    }

    func testDeleteMailboxCache() throws {
        let selection = SidebarSelection.allAccounts(.inbox)
        let cache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date(),
            nextPageToken: nil,
            hasMorePages: false
        ))

        try sut.saveMailboxCache(cache, for: selection)
        try sut.deleteMailboxCache(for: selection)

        let loaded = try sut.loadMailboxCache(for: selection)
        XCTAssertNil(loaded)
    }

    func testDeleteAllMailboxCaches() throws {
        let inbox = SidebarSelection.allAccounts(.inbox)
        let sent = SidebarSelection.allAccounts(.sent)
        let cache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date(),
            nextPageToken: nil,
            hasMorePages: false
        ))

        try sut.saveMailboxCache(cache, for: inbox)
        try sut.saveMailboxCache(cache, for: sent)
        try sut.deleteAllMailboxCaches()

        XCTAssertNil(try sut.loadMailboxCache(for: inbox))
        XCTAssertNil(try sut.loadMailboxCache(for: sent))
    }

    func testMailboxCache_differentSelections_independent() throws {
        let inbox = SidebarSelection.allAccounts(.inbox)
        let sent = SidebarSelection.allAccounts(.sent)

        let inboxCache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date(),
            nextPageToken: nil,
            hasMorePages: false
        ))
        let sentCache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.readMessage],
            fetchedAt: Date(),
            nextPageToken: nil,
            hasMorePages: false
        ))

        try sut.saveMailboxCache(inboxCache, for: inbox)
        try sut.saveMailboxCache(sentCache, for: sent)

        let loadedInbox = try sut.loadMailboxCache(for: inbox)
        let loadedSent = try sut.loadMailboxCache(for: sent)

        XCTAssertEqual(loadedInbox?.messages.first?.id, Message.testMessage.id)
        XCTAssertEqual(loadedSent?.messages.first?.id, Message.readMessage.id)
    }

    func testMailboxCache_accountScoped() throws {
        let sel = SidebarSelection.account(.inbox, accountId: "acc-1")
        let cache = PersistableMailboxCache(from: CachedMailbox(
            messages: [Message.testMessage],
            fetchedAt: Date(),
            nextPageToken: nil,
            hasMorePages: false
        ))

        try sut.saveMailboxCache(cache, for: sel)
        let loaded = try sut.loadMailboxCache(for: sel)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.messages.count, 1)
    }

    // MARK: - Preferences

    func testSaveAndLoadPreferences() throws {
        var prefs = UserPreferences()
        prefs.checkIntervalMinutes = 10
        prefs.notificationsEnabled = false

        try sut.savePreferences(prefs)
        let loaded = try sut.loadPreferences()

        XCTAssertEqual(loaded.checkIntervalMinutes, 10)
        XCTAssertFalse(loaded.notificationsEnabled)
    }

    func testLoadPreferences_noData_returnsDefault() throws {
        let loaded = try sut.loadPreferences()

        XCTAssertEqual(loaded.checkIntervalMinutes, UserPreferences.default.checkIntervalMinutes)
        XCTAssertEqual(loaded.notificationsEnabled, UserPreferences.default.notificationsEnabled)
    }

    // MARK: - VersionedStore

    func testCorruptFile_returnsNilAndCreatesBackup() throws {
        // C2: Write garbage to the accounts file
        let accountsFile = testDirectory.appendingPathComponent("accounts.json")
        let backupFile = accountsFile.appendingPathExtension("bak")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try "not valid json {{{".data(using: .utf8)!.write(to: accountsFile)

        let loaded = try sut.loadAccounts()
        XCTAssertTrue(loaded.isEmpty)

        // Corrupt file should have been cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountsFile.path))
        // C2: Backup should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path))
        // Backup content should match the original corrupt data
        let backupData = try Data(contentsOf: backupFile)
        XCTAssertEqual(String(data: backupData, encoding: .utf8), "not valid json {{{")
    }

    func testFutureVersion_preservesFileAndReturnsEmpty() throws {
        // C1: A future version file should not be deleted
        let accountsFile = testDirectory.appendingPathComponent("accounts.json")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Write a valid JSON with future version
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let futureStore = "{\"version\":999,\"payload\":[]}"
        try futureStore.data(using: .utf8)!.write(to: accountsFile)

        let loaded = try sut.loadAccounts()
        XCTAssertTrue(loaded.isEmpty)

        // C1: File should be preserved (not deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountsFile.path))
    }

    // MARK: - Local Drafts

    func testSaveAndLoadLocalDraft() throws {
        let draft = LocalDraft(to: "a@b.com", cc: "", bcc: "", subject: "Test", body: "Hello")
        try sut.saveLocalDraft(draft)

        let loaded = try sut.loadLocalDraft(id: draft.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.to, "a@b.com")
        XCTAssertEqual(loaded?.subject, "Test")
    }

    func testDeleteLocalDraft() throws {
        let draft = LocalDraft(to: "a@b.com", subject: "Test")
        try sut.saveLocalDraft(draft)
        try sut.deleteLocalDraft(id: draft.id)

        let loaded = try sut.loadLocalDraft(id: draft.id)
        XCTAssertNil(loaded)
    }

    func testLoadAllLocalDrafts() throws {
        let draft1 = LocalDraft(to: "a@b.com", subject: "Draft 1")
        let draft2 = LocalDraft(to: "c@d.com", subject: "Draft 2")
        try sut.saveLocalDraft(draft1)
        try sut.saveLocalDraft(draft2)

        let all = try sut.loadAllLocalDrafts()
        XCTAssertEqual(all.count, 2)
    }

    func testCacheAge() {
        let oldCache = PersistableMailboxCache(from: CachedMailbox(
            messages: [],
            fetchedAt: Date().addingTimeInterval(-7200),
            nextPageToken: nil,
            hasMorePages: false
        ))
        XCTAssertGreaterThan(oldCache.age, 7100) // ~2 hours

        let freshCache = PersistableMailboxCache(from: CachedMailbox(
            messages: [],
            fetchedAt: Date(),
            nextPageToken: nil,
            hasMorePages: false
        ))
        XCTAssertLessThan(freshCache.age, 5)
    }
}

// MARK: - Model Codable Round-Trip Tests

final class ModelCodableTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func testMessage_codableRoundTrip() throws {
        let message = Message.testMessage
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(Message.self, from: data)

        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.subject, message.subject)
        XCTAssertEqual(decoded.from, message.from)
        XCTAssertEqual(decoded.to, message.to)
        XCTAssertEqual(decoded.isRead, message.isRead)
        XCTAssertEqual(decoded.isStarred, message.isStarred)
        XCTAssertEqual(decoded.labelIds, message.labelIds)
    }

    func testSidebarSelection_allAccounts_codableRoundTrip() throws {
        let selection = SidebarSelection.allAccounts(.starred)
        let data = try encoder.encode(selection)
        let decoded = try decoder.decode(SidebarSelection.self, from: data)

        XCTAssertEqual(decoded, selection)
    }

    func testSidebarSelection_account_codableRoundTrip() throws {
        let selection = SidebarSelection.account(.drafts, accountId: "acc-42")
        let data = try encoder.encode(selection)
        let decoded = try decoder.decode(SidebarSelection.self, from: data)

        XCTAssertEqual(decoded, selection)
    }

    func testPersistableAccount_codableRoundTrip() throws {
        let account = Account.testAccount
        let persistable = PersistableAccount(from: account)
        let data = try encoder.encode(persistable)
        let decoded = try decoder.decode(PersistableAccount.self, from: data)

        XCTAssertEqual(decoded.id, persistable.id)
        XCTAssertEqual(decoded.email, persistable.email)
        XCTAssertEqual(decoded.displayName, persistable.displayName)
        XCTAssertEqual(decoded.isActive, persistable.isActive)
    }
}
