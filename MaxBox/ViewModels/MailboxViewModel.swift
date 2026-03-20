import Foundation
import Combine

@MainActor
final class MailboxViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var selectedMailboxType: MailboxType = .inbox
    @Published var selectedAccountId: String? // nil = unified
    @Published var isSigningIn = false
    @Published var authError: String?

    let authService: AuthenticationServiceProtocol
    let gmailService: GmailAPIServiceProtocol

    var mailboxes: [Mailbox] {
        if let accountId = selectedAccountId {
            return MailboxType.allCases.map { Mailbox(type: $0, accountId: accountId) }
        }
        // Unified: show one entry per type
        return MailboxType.allCases.map { Mailbox(type: $0, accountId: "unified") }
    }

    var activeAccounts: [Account] {
        accounts.filter { $0.isAuthenticated }
    }

    init(
        authService: AuthenticationServiceProtocol? = nil,
        gmailService: GmailAPIServiceProtocol? = nil
    ) {
        self.authService = authService ?? AuthenticationService()
        self.gmailService = gmailService ?? GmailAPIService()
    }

    func addAccount() async {
        isSigningIn = true
        authError = nil

        do {
            let account = try await authService.signIn()
            if !accounts.contains(where: { $0.id == account.id }) {
                accounts.append(account)
            } else {
                // Update existing account
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index] = account
                }
            }
        } catch {
            authError = error.localizedDescription
        }

        isSigningIn = false
    }

    func removeAccount(_ account: Account) async {
        do {
            try await authService.signOut(account: account)
        } catch {
            // Best effort
        }
        accounts.removeAll { $0.id == account.id }
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
}
