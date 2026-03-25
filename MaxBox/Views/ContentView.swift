import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @StateObject private var messageListVM = MessageListViewModel()
    @StateObject private var messageDetailVM = MessageDetailViewModel()
    @State private var hasPromptedForAccount = false
    @State private var showTrashConfirmation = false
    @State private var showArchiveConfirmation = false

    private var messageActions: MessageActions? {
        guard messageDetailVM.message != nil else { return nil }
        return MessageActions(
            reply: { replyToMessage() },
            replyAll: { replyAllToMessage() },
            forward: { forwardMessage() },
            archive: { showArchiveConfirmation = true },
            trash: { showTrashConfirmation = true }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            MessageListView(viewModel: messageListVM)
        } detail: {
            MessageDetailView(viewModel: messageDetailVM)
        }
        .navigationSplitViewStyle(.balanced)
        .focusedSceneValue(\.messageActions, messageActions)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { openWindow(id: "compose", value: UUID()) } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .help("Compose new message")
            }

            ToolbarItem(placement: .automatic) {
                Button { replyToMessage() } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .help("Reply")
                .disabled(messageDetailVM.message == nil)
            }

            ToolbarItem(placement: .automatic) {
                Button { replyAllToMessage() } label: {
                    Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                }
                .help("Reply All")
                .disabled(messageDetailVM.message == nil)
            }

            ToolbarItem(placement: .automatic) {
                Button { forwardMessage() } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
                .help("Forward")
                .disabled(messageDetailVM.message == nil)
            }

            ToolbarItem(placement: .automatic) {
                Button { showArchiveConfirmation = true } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("Archive message")
                .disabled(messageDetailVM.message == nil)
            }

            ToolbarItem(placement: .automatic) {
                Button { showTrashConfirmation = true } label: {
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
        .task {
            if mailboxVM.accounts.isEmpty && !hasPromptedForAccount {
                hasPromptedForAccount = true
                openSettings()
            } else if !mailboxVM.activeAccounts.isEmpty {
                await refreshMessages()
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
        // H1: Confirmation dialogs for destructive actions
        .alert("Move to Trash?", isPresented: $showTrashConfirmation) {
            Button("Trash", role: .destructive) {
                Task { await trashMessage() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This message will be moved to the trash. You can recover it from Gmail within 30 days.")
        }
        .alert("Archive Message?", isPresented: $showArchiveConfirmation) {
            Button("Archive", role: .destructive) {
                Task { await archiveMessage() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This message will be removed from the inbox.")
        }
        // H3: Surface persistence errors to user
        .alert("Storage Error", isPresented: .init(
            get: { mailboxVM.persistenceError != nil },
            set: { if !$0 { mailboxVM.persistenceError = nil } }
        )) {
            Button("OK") { mailboxVM.persistenceError = nil }
        } message: {
            Text(mailboxVM.persistenceError ?? "")
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

    private func buildComposeContext(mode: ComposeMode) -> ComposeContext? {
        guard let message = messageDetailVM.message else { return nil }
        let accountId = message.accountId ?? mailboxVM.selectedAccountId ?? mailboxVM.activeAccounts.first?.id ?? ""
        return ComposeContext(
            mode: mode,
            accountId: accountId,
            originalFrom: message.from,
            originalTo: message.to,
            originalCc: message.cc,
            originalSubject: message.subject,
            originalDate: message.date,
            originalBody: message.body,
            originalBodyHTML: message.bodyHTML
        )
    }

    private func replyToMessage() {
        guard let ctx = buildComposeContext(mode: .reply) else { return }
        openWindow(id: "compose-reply", value: ctx)
    }

    private func replyAllToMessage() {
        guard let ctx = buildComposeContext(mode: .replyAll) else { return }
        openWindow(id: "compose-reply", value: ctx)
    }

    private func forwardMessage() {
        guard let ctx = buildComposeContext(mode: .forward) else { return }
        openWindow(id: "compose-reply", value: ctx)
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
