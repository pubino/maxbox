import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.maxbox.MaxBox", category: "Mailbox")

@MainActor
final class MailboxViewModel: ObservableObject {
    @Published var accounts: [Account] = [] {
        didSet {
            guard !isRestoring else { return }
            persistAccounts()
        }
    }
    @Published var selection: SidebarSelection = .allAccounts(.inbox) {
        didSet {
            guard !isRestoring else { return }
            persistSelection()
        }
    }
    @Published var isSigningIn = false
    @Published var authError: String?
    @Published var showAddAccountDialog = false
    /// H3: User-visible banner for persistence or background errors.
    @Published var persistenceError: String?

    let authService: AuthenticationServiceProtocol
    let gmailService: GmailAPIServiceProtocol
    let persistenceService: PersistenceServiceProtocol
    let keychainService: KeychainServiceProtocol

    private var signInTask: Task<Void, Never>?
    private var cacheBuildTask: Task<Void, Never>?
    private var isRestoring = false

    let activityManager: ActivityManager

    /// Mailbox types to prefetch when a new account is added.
    static let prefetchMailboxTypes: [MailboxType] = [.inbox, .sent, .drafts]

    var selectedMailboxType: MailboxType {
        selection.mailboxType
    }

    var selectedAccountId: String? {
        selection.accountId
    }

    var isMultiAccount: Bool {
        activeAccounts.count > 1
    }

    var mailboxes: [Mailbox] {
        if let accountId = selectedAccountId {
            return MailboxType.allCases.map { Mailbox(type: $0, accountId: accountId) }
        }
        return MailboxType.allCases.map { Mailbox(type: $0, accountId: "unified") }
    }

    var activeAccounts: [Account] {
        accounts.filter { $0.isAuthenticated && $0.isActive }
    }

    init(
        authService: AuthenticationServiceProtocol? = nil,
        gmailService: GmailAPIServiceProtocol? = nil,
        persistenceService: PersistenceServiceProtocol? = nil,
        keychainService: KeychainServiceProtocol? = nil,
        activityManager: ActivityManager? = nil,
        skipRestore: Bool = false
    ) {
        self.authService = authService ?? AuthenticationService()
        self.gmailService = gmailService ?? GmailAPIService()
        self.persistenceService = persistenceService ?? PersistenceService()
        self.keychainService = keychainService ?? KeychainService()
        self.activityManager = activityManager ?? .shared
        if !skipRestore {
            restoreState()
        }
    }

    func addAccount() async {
        // Cancel any in-flight sign-in so the user can start fresh
        signInTask?.cancel()
        signInTask = nil

        isSigningIn = true
        authError = nil

        let task = Task {
            do {
                try Task.checkCancellation()
                let account = try await authService.signIn()
                try Task.checkCancellation()
                let isNew = !accounts.contains(where: { $0.id == account.id })
                if isNew {
                    accounts.append(account)
                } else {
                    if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                        accounts[index] = account
                    }
                }
                // Begin background cache build for the new account
                if isNew {
                    buildInitialCaches(for: account)
                }
            } catch is CancellationError {
                // Silently cancelled — another sign-in is taking over
            } catch {
                authError = error.localizedDescription
            }
            isSigningIn = false
        }
        signInTask = task
        await task.value
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        isSigningIn = false
        authError = nil
    }

    func removeAccount(_ account: Account) async {
        cacheBuildTask?.cancel()
        cacheBuildTask = nil
        do {
            try await authService.signOut(account: account)
        } catch {
            // Best effort
        }
        cleanupCaches(for: account)
        accounts.removeAll { $0.id == account.id }
    }

    func toggleAccountActive(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].isActive.toggle()
    }

    func getAccessToken(for accountId: String) async throws -> String {
        guard let account = accounts.first(where: { $0.id == accountId }) else {
            throw AuthError.notAuthenticated
        }
        do {
            return try await authService.getValidAccessToken(for: account)
        } catch let error as AuthError {
            // H2: Surface token revocation to user
            if case .tokenRevoked = error {
                authError = "\(account.email): \(error.localizedDescription)"
            }
            throw error
        }
    }

    func getAccessTokens() async throws -> [(accountId: String, token: String)] {
        var tokens: [(String, String)] = []
        for account in activeAccounts {
            do {
                let token = try await authService.getValidAccessToken(for: account)
                tokens.append((account.id, token))
            } catch let error as AuthError {
                if case .tokenRevoked = error {
                    authError = "\(account.email): \(error.localizedDescription)"
                }
                throw error
            }
        }
        return tokens
    }

    func accountEmail(for accountId: String) -> String? {
        accounts.first(where: { $0.id == accountId })?.email
    }

    // MARK: - Background cache build

    /// Kick off a background fetch of inbox, sent, and drafts for a newly added account.
    /// The results are written directly to disk cache so they're available when the user
    /// navigates to those mailboxes.
    func buildInitialCaches(for account: Account) {
        cacheBuildTask?.cancel()
        let accountId = account.id
        let gmail = gmailService
        let auth = authService
        let persistence = persistenceService
        let activity = activityManager
        let mailboxTypes = Self.prefetchMailboxTypes

        cacheBuildTask = Task { [weak self] in
            let activityId = activity.start(
                "Caching messages for \(account.email)",
                total: mailboxTypes.count
            )

            var completedCount = 0
            for mailboxType in mailboxTypes {
                guard !Task.isCancelled else { break }
                let selection = SidebarSelection.account(mailboxType, accountId: accountId)
                let labelId = mailboxType.gmailLabelId

                do {
                    let token = try await auth.getValidAccessToken(for: account)
                    let response = try await gmail.listMessages(
                        accessToken: token,
                        labelId: labelId,
                        query: nil,
                        pageToken: nil,
                        maxResults: 25
                    )

                    guard !Task.isCancelled else { break }

                    var messages: [Message] = []
                    for ref in (response.messages ?? []) {
                        guard !Task.isCancelled else { break }
                        do {
                            var msg = try await gmail.getMessage(
                                accessToken: token,
                                messageId: ref.id
                            )
                            msg.accountId = accountId
                            messages.append(msg)
                        } catch {
                            // Skip individual failures
                        }
                    }

                    guard !Task.isCancelled else { break }

                    let cached = PersistableMailboxCache(from: CachedMailbox(
                        messages: messages,
                        fetchedAt: Date(),
                        nextPageToken: response.nextPageToken,
                        hasMorePages: response.nextPageToken != nil
                    ))
                    try? persistence.saveMailboxCache(cached, for: selection)

                    // Also populate the in-memory cache on the MessageListViewModel
                    // via the shared persistence layer — the VM will pick it up on next switch.
                } catch {
                    // Token or list call failed — skip this mailbox
                }

                completedCount += 1
                activity.update(activityId, current: completedCount)
            }

            if Task.isCancelled {
                activity.fail(activityId, error: "Cancelled")
            } else {
                activity.complete(activityId)
            }

            // Clear self-reference
            await self?.clearCacheBuildTask()
        }
    }

    private func clearCacheBuildTask() {
        cacheBuildTask = nil
    }

    // MARK: - Persistence

    func restoreState() {
        isRestoring = true
        defer { isRestoring = false }

        // Restore accounts from disk, merging tokens from Keychain
        if let persisted = try? persistenceService.loadAccounts() {
            accounts = persisted.map { pa in
                let accessToken = try? keychainService.read(key: "access_token_\(pa.id)")
                let refreshToken = try? keychainService.read(key: "refresh_token_\(pa.id)")
                return pa.toAccount(accessToken: accessToken, refreshToken: refreshToken)
            }
        }

        // Restore last sidebar selection
        if let savedSelection = try? persistenceService.loadSelection() {
            // Validate the selection still makes sense
            switch savedSelection {
            case .account(_, let accountId):
                if accounts.contains(where: { $0.id == accountId }) {
                    selection = savedSelection
                }
            case .allAccounts:
                selection = savedSelection
            }
        }
    }

    private func persistAccounts() {
        let persistable = accounts.map { PersistableAccount(from: $0) }
        do {
            try persistenceService.saveAccounts(persistable)
            persistenceError = nil
        } catch {
            logger.error("Failed to save accounts: \(error.localizedDescription)")
            persistenceError = "Could not save account data — \(error.localizedDescription)"
        }
    }

    private func persistSelection() {
        do {
            try persistenceService.saveSelection(selection)
        } catch {
            logger.error("Failed to save selection: \(error.localizedDescription)")
        }
    }

    func cleanupCaches(for account: Account) {
        // Delete per-account caches for all mailbox types
        for mailboxType in MailboxType.allCases {
            try? persistenceService.deleteMailboxCache(for: .account(mailboxType, accountId: account.id))
        }
        // Also clear allAccounts caches since they contain this account's messages
        for mailboxType in MailboxType.allCases {
            try? persistenceService.deleteMailboxCache(for: .allAccounts(mailboxType))
        }
    }
}
