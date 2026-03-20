import Foundation
@testable import MaxBox

// MARK: - Mock Authentication Service

final class MockAuthenticationService: AuthenticationServiceProtocol {
    var isAuthenticated: Bool = false
    var signInResult: Result<Account, Error> = .failure(AuthError.noClientId)
    var signOutError: Error?
    var refreshResult: Result<Account, Error>?
    var accessTokenResult: Result<String, Error> = .success("mock-access-token")

    var signInCallCount = 0
    var signOutCallCount = 0
    var refreshCallCount = 0
    var getValidAccessTokenCallCount = 0
    var lastSignedOutAccount: Account?

    func signIn() async throws -> Account {
        signInCallCount += 1
        switch signInResult {
        case .success(let account):
            isAuthenticated = true
            return account
        case .failure(let error):
            throw error
        }
    }

    func signOut(account: Account) async throws {
        signOutCallCount += 1
        lastSignedOutAccount = account
        if let error = signOutError {
            throw error
        }
        isAuthenticated = false
    }

    func refreshTokenIfNeeded(account: Account) async throws -> Account {
        refreshCallCount += 1
        if let result = refreshResult {
            switch result {
            case .success(let acc): return acc
            case .failure(let err): throw err
            }
        }
        return account
    }

    func getValidAccessToken(for account: Account) async throws -> String {
        getValidAccessTokenCallCount += 1
        switch accessTokenResult {
        case .success(let token): return token
        case .failure(let error): throw error
        }
    }
}

// MARK: - Mock Gmail API Service

final class MockGmailAPIService: GmailAPIServiceProtocol {
    var listMessagesResult: Result<MessageListResponse, Error> = .success(
        MessageListResponse(messages: nil, nextPageToken: nil, resultSizeEstimate: 0)
    )
    var getMessageResult: Result<Message, Error> = .success(Message.placeholder)
    var modifyMessageError: Error?
    var trashMessageError: Error?
    var archiveMessageError: Error?
    var sendMessageError: Error?

    var listMessagesCallCount = 0
    var getMessageCallCount = 0
    var modifyMessageCallCount = 0
    var trashMessageCallCount = 0
    var archiveMessageCallCount = 0
    var sendMessageCallCount = 0

    var lastListAccessToken: String?
    var lastListLabelId: String?
    var lastListQuery: String?
    var lastListPageToken: String?
    var lastModifyAddLabels: [String]?
    var lastModifyRemoveLabels: [String]?
    var lastModifyMessageId: String?
    var lastTrashMessageId: String?
    var lastArchiveMessageId: String?
    var lastSendTo: String?
    var lastSendSubject: String?
    var lastSendBody: String?
    var lastSendCc: String?

    func listMessages(accessToken: String, labelId: String, query: String?, pageToken: String?, maxResults: Int) async throws -> MessageListResponse {
        listMessagesCallCount += 1
        lastListAccessToken = accessToken
        lastListLabelId = labelId
        lastListQuery = query
        lastListPageToken = pageToken
        switch listMessagesResult {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    func getMessage(accessToken: String, messageId: String) async throws -> Message {
        getMessageCallCount += 1
        switch getMessageResult {
        case .success(let message):
            return Message(
                id: messageId,
                threadId: message.threadId,
                subject: message.subject,
                from: message.from,
                to: message.to,
                cc: message.cc,
                date: message.date,
                snippet: message.snippet,
                body: message.body,
                isRead: message.isRead,
                isStarred: message.isStarred,
                labelIds: message.labelIds
            )
        case .failure(let error):
            throw error
        }
    }

    func modifyMessage(accessToken: String, messageId: String, addLabels: [String], removeLabels: [String]) async throws {
        modifyMessageCallCount += 1
        lastModifyMessageId = messageId
        lastModifyAddLabels = addLabels
        lastModifyRemoveLabels = removeLabels
        if let error = modifyMessageError {
            throw error
        }
    }

    func trashMessage(accessToken: String, messageId: String) async throws {
        trashMessageCallCount += 1
        lastTrashMessageId = messageId
        if let error = trashMessageError {
            throw error
        }
    }

    func archiveMessage(accessToken: String, messageId: String) async throws {
        archiveMessageCallCount += 1
        lastArchiveMessageId = messageId
        if let error = archiveMessageError {
            throw error
        }
    }

    func sendMessage(accessToken: String, to: String, subject: String, body: String, cc: String?) async throws {
        sendMessageCallCount += 1
        lastSendTo = to
        lastSendSubject = subject
        lastSendBody = body
        lastSendCc = cc
        if let error = sendMessageError {
            throw error
        }
    }
}

// MARK: - Mock Keychain Service

final class MockKeychainService: KeychainServiceProtocol {
    var storage: [String: String] = [:]
    var saveError: Error?
    var readError: Error?
    var deleteError: Error?

    var saveCallCount = 0
    var readCallCount = 0
    var deleteCallCount = 0

    func save(key: String, value: String) throws {
        saveCallCount += 1
        if let error = saveError { throw error }
        storage[key] = value
    }

    func read(key: String) throws -> String? {
        readCallCount += 1
        if let error = readError { throw error }
        return storage[key]
    }

    func delete(key: String) throws {
        deleteCallCount += 1
        if let error = deleteError { throw error }
        storage.removeValue(forKey: key)
    }
}

// MARK: - Test Helpers

extension Account {
    static let testAccount = Account(
        id: "test-123",
        email: "test@gmail.com",
        displayName: "Test User",
        accessToken: "test-access-token",
        refreshToken: "test-refresh-token",
        tokenExpiry: Date().addingTimeInterval(3600)
    )

    static let expiredAccount = Account(
        id: "expired-456",
        email: "expired@gmail.com",
        displayName: "Expired User",
        accessToken: "old-token",
        refreshToken: "refresh-token",
        tokenExpiry: Date().addingTimeInterval(-100)
    )

    static let noTokenAccount = Account(
        id: "notoken-789",
        email: "notoken@gmail.com",
        displayName: "No Token User",
        accessToken: nil,
        refreshToken: nil,
        tokenExpiry: nil
    )
}

extension Message {
    static let testMessage = Message(
        id: "msg-001",
        threadId: "thread-001",
        subject: "Test Subject",
        from: "Alice Smith <alice@example.com>",
        to: ["bob@example.com"],
        cc: ["charlie@example.com"],
        date: Date(),
        snippet: "This is a test message snippet...",
        body: "Full body of the test message.",
        isRead: false,
        isStarred: false,
        labelIds: ["INBOX", "UNREAD"]
    )

    static let readMessage = Message(
        id: "msg-002",
        threadId: "thread-002",
        subject: "Read Message",
        from: "Bob <bob@example.com>",
        to: ["test@gmail.com"],
        cc: [],
        date: Date().addingTimeInterval(-86400),
        snippet: "Already read...",
        body: "This message was read.",
        isRead: true,
        isStarred: true,
        labelIds: ["INBOX", "STARRED"]
    )
}
