import Foundation
import Combine

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

    let authService: AuthenticationServiceProtocol
    let gmailService: GmailAPIServiceProtocol
    let persistenceService: PersistenceServiceProtocol
    let keychainService: KeychainServiceProtocol

    private var signInTask: Task<Void, Never>?
    private var isRestoring = false

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
        skipRestore: Bool = false
    ) {
        self.authService = authService ?? AuthenticationService()
        self.gmailService = gmailService ?? GmailAPIService()
        self.persistenceService = persistenceService ?? PersistenceService()
        self.keychainService = keychainService ?? KeychainService()
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
                if !accounts.contains(where: { $0.id == account.id }) {
                    accounts.append(account)
                } else {
                    if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                        accounts[index] = account
                    }
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
        return try await authService.getValidAccessToken(for: account)
    }

    func getAccessTokens() async throws -> [(accountId: String, token: String)] {
        var tokens: [(String, String)] = []
        for account in activeAccounts {
            let token = try await authService.getValidAccessToken(for: account)
            tokens.append((account.id, token))
        }
        return tokens
    }

    func accountEmail(for accountId: String) -> String? {
        accounts.first(where: { $0.id == accountId })?.email
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
        try? persistenceService.saveAccounts(persistable)
    }

    private func persistSelection() {
        try? persistenceService.saveSelection(selection)
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
