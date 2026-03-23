import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @StateObject private var messageListVM = MessageListViewModel()
    @StateObject private var messageDetailVM = MessageDetailViewModel()
    @State private var hasPromptedForAccount = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            MessageListView(viewModel: messageListVM)
        } detail: {
            MessageDetailView(viewModel: messageDetailVM)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { openWindow(id: "compose", value: UUID()) } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .help("Compose new message")
            }

            ToolbarItem(placement: .automatic) {
                Button { Task { await archiveMessage() } } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("Archive message")
                .disabled(messageDetailVM.message == nil)
            }

            ToolbarItem(placement: .automatic) {
                Button { Task { await trashMessage() } } label: {
                    Label("Trash", systemImage: "trash")
                }
                .help("Move to trash")
                .disabled(messageDetailVM.message == nil)
            }

            ToolbarItem(placement: .automatic) {
                SearchBar(searchQuery: $messageListVM.searchQuery) {
                    Task { await refreshMessages(forceRefresh: true) }
                }
            }
        }
        .onChange(of: mailboxVM.selection) {
            Task { await refreshMessages() }
        }
        .onChange(of: messageListVM.selectedMessageId) {
            if let id = messageListVM.selectedMessageId {
                Task { await loadMessageDetail(id: id) }
            } else {
                messageDetailVM.message = nil
            }
        }
        .onAppear {
            if mailboxVM.accounts.isEmpty && !hasPromptedForAccount {
                hasPromptedForAccount = true
                openSettings()
            }
        }
        .onChange(of: mailboxVM.showAddAccountDialog) {
            if mailboxVM.showAddAccountDialog {
                mailboxVM.showAddAccountDialog = false
                Task { await mailboxVM.addAccount() }
            }
        }
        .alert("Authentication Error", isPresented: .init(
            get: { mailboxVM.authError != nil },
            set: { if !$0 { mailboxVM.authError = nil } }
        )) {
            Button("OK") { mailboxVM.authError = nil }
        } message: {
            Text(mailboxVM.authError ?? "")
        }
    }

    private func refreshMessages(forceRefresh: Bool = false) async {
        let selection = mailboxVM.selection
        guard let tokens = try? await resolveTokens(for: selection), !tokens.isEmpty else { return }

        await messageListVM.switchMailbox(
            selection: selection,
            tokens: tokens,
            forceRefresh: forceRefresh
        )
    }

    private func resolveTokens(for selection: SidebarSelection) async throws -> [(accountId: String, token: String)] {
        switch selection {
        case .allAccounts:
            return try await mailboxVM.getAccessTokens()
        case .account(_, let accountId):
            let token = try await mailboxVM.getAccessToken(for: accountId)
            return [(accountId, token)]
        }
    }

    private func archiveMessage() async {
        guard let message = messageDetailVM.message,
              let token = await getAccessTokenForSelectedMessage() else { return }
        let success = await messageDetailVM.archiveMessage(accessToken: token)
        if success {
            let messageId = message.id
            messageDetailVM.message = nil
            messageListVM.selectedMessageId = nil
            messageListVM.removeMessage(id: messageId)
        }
    }

    private func trashMessage() async {
        guard let message = messageDetailVM.message,
              let token = await getAccessTokenForSelectedMessage() else { return }
        let success = await messageDetailVM.trashMessage(accessToken: token)
        if success {
            let messageId = message.id
            messageDetailVM.message = nil
            messageListVM.selectedMessageId = nil
            messageListVM.removeMessage(id: messageId)
        }
    }

    private func getAccessTokenForSelectedMessage() async -> String? {
        if let accountId = messageDetailVM.message?.accountId {
            return try? await mailboxVM.getAccessToken(for: accountId)
        }
        if let accountId = mailboxVM.selectedAccountId {
            return try? await mailboxVM.getAccessToken(for: accountId)
        }
        guard let account = mailboxVM.activeAccounts.first else { return nil }
        return try? await mailboxVM.getAccessToken(for: account.id)
    }

    private func loadMessageDetail(id: String) async {
        guard let token = await getAccessTokenForMessage(id: id) else { return }
        await messageDetailVM.loadMessage(accessToken: token, messageId: id)
        await messageListVM.markAsRead(accessToken: token, messageId: id)
    }

    private func getAccessTokenForMessage(id: String) async -> String? {
        if let message = messageListVM.messages.first(where: { $0.id == id }),
           let accountId = message.accountId {
            return try? await mailboxVM.getAccessToken(for: accountId)
        }
        if let accountId = mailboxVM.selectedAccountId {
            return try? await mailboxVM.getAccessToken(for: accountId)
        }
        guard let account = mailboxVM.activeAccounts.first else { return nil }
        return try? await mailboxVM.getAccessToken(for: account.id)
    }
}

#Preview {
    ContentView()
        .environmentObject(MailboxViewModel())
        .environmentObject(ActivityManager.shared)
}
