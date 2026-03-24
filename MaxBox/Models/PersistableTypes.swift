import Foundation

// MARK: - Versioned Store Envelope

struct VersionedStore<T: Codable>: Codable {
    static var currentVersion: Int { 1 }

    let version: Int
    let payload: T

    init(payload: T) {
        self.version = Self.currentVersion
        self.payload = payload
    }
}

// MARK: - PersistableAccount (tokens excluded — they stay in Keychain)

struct PersistableAccount: Codable, Equatable {
    let id: String
    var email: String
    var displayName: String
    var tokenExpiry: Date?
    var isActive: Bool

    init(from account: Account) {
        self.id = account.id
        self.email = account.email
        self.displayName = account.displayName
        self.tokenExpiry = account.tokenExpiry
        self.isActive = account.isActive
    }

    func toAccount(accessToken: String?, refreshToken: String?) -> Account {
        Account(
            id: id,
            email: email,
            displayName: displayName,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiry: tokenExpiry,
            isActive: isActive
        )
    }
}

// MARK: - PersistableMailboxCache

struct PersistableMailboxCache: Codable {
    let messages: [Message]
    let fetchedAt: Date
    let nextPageToken: String?
    let hasMorePages: Bool

    init(from cached: CachedMailbox) {
        self.messages = cached.messages
        self.fetchedAt = cached.fetchedAt
        self.nextPageToken = cached.nextPageToken
        self.hasMorePages = cached.hasMorePages
    }

    func toCachedMailbox() -> CachedMailbox {
        CachedMailbox(
            messages: messages,
            fetchedAt: fetchedAt,
            nextPageToken: nextPageToken,
            hasMorePages: hasMorePages
        )
    }

    var age: TimeInterval {
        Date().timeIntervalSince(fetchedAt)
    }
}

// MARK: - Local Draft (fallback when Gmail API is unreachable)

struct LocalDraft: Codable, Identifiable {
    let id: UUID
    var to: String
    var cc: String
    var bcc: String
    var subject: String
    var body: String
    var accountId: String?
    var remoteDraftId: String?
    var savedAt: Date

    init(to: String = "", cc: String = "", bcc: String = "", subject: String = "", body: String = "", accountId: String? = nil, remoteDraftId: String? = nil) {
        self.id = UUID()
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.accountId = accountId
        self.remoteDraftId = remoteDraftId
        self.savedAt = Date()
    }
}

// MARK: - UserPreferences

struct UserPreferences: Codable, Equatable {
    var checkIntervalMinutes: Int = 5
    var notificationsEnabled: Bool = true

    static let `default` = UserPreferences()
}
