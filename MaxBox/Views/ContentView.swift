import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @StateObject private var messageListVM = MessageListViewModel()
    @StateObject private var messageDetailVM = MessageDetailViewModel()
    @State private var showCompose = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            MessageListView(
                viewModel: messageListVM,
                onComposeClicked: { showCompose = true }
            )
        } detail: {
            MessageDetailView(viewModel: messageDetailVM)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SearchBar(searchQuery: $messageListVM.searchQuery) {
                    Task { await refreshMessages() }
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(
                isPresented: $showCompose,
                mailboxVM: mailboxVM
            )
        }
        .onChange(of: mailboxVM.selectedMailboxType) {
            Task { await refreshMessages() }
        }
        .onChange(of: mailboxVM.selectedAccountId) {
            Task { await refreshMessages() }
        }
        .onChange(of: messageListVM.selectedMessageId) {
            if let id = messageListVM.selectedMessageId {
                Task { await loadMessageDetail(id: id) }
            } else {
                messageDetailVM.message = nil
            }
        }
    }

    private func refreshMessages() async {
        guard let token = await getFirstAccessToken() else { return }
        await messageListVM.loadMessages(
            accessToken: token,
            labelId: mailboxVM.selectedMailboxType.gmailLabelId
        )
    }

    private func loadMessageDetail(id: String) async {
        guard let token = await getFirstAccessToken() else { return }
        await messageDetailVM.loadMessage(accessToken: token, messageId: id)
        // Mark as read
        await messageListVM.markAsRead(accessToken: token, messageId: id)
    }

    private func getFirstAccessToken() async -> String? {
        guard let account = mailboxVM.activeAccounts.first else { return nil }
        return try? await mailboxVM.getAccessToken(for: account.id)
    }
}

#Preview {
    ContentView()
        .environmentObject(MailboxViewModel())
}
