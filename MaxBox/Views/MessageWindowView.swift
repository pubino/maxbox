import SwiftUI

struct MessageWindowView: View {
    let context: MessageWindowContext
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MessageDetailViewModel()
    @State private var actionInProgress = false

    var body: some View {
        MessageDetailView(viewModel: viewModel)
            .frame(minWidth: 500, minHeight: 400)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button { replyToMessage() } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    .help("Reply")
                    .disabled(viewModel.message == nil)

                    Button { replyAllToMessage() } label: {
                        Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                    }
                    .help("Reply All")
                    .disabled(viewModel.message == nil)

                    Button { forwardMessage() } label: {
                        Label("Forward", systemImage: "arrowshape.turn.up.right")
                    }
                    .help("Forward")
                    .disabled(viewModel.message == nil)

                    Spacer()

                    Button { Task { await archiveMessage() } } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .help("Archive")
                    .disabled(viewModel.message == nil || actionInProgress)

                    Button { Task { await trashMessage() } } label: {
                        Label("Trash", systemImage: "trash")
                    }
                    .help("Move to trash")
                    .disabled(viewModel.message == nil || actionInProgress)
                }
            }
            .onAppear {
                Task { await loadMessage() }
            }
    }

    private func loadMessage() async {
        guard let token = try? await mailboxVM.getAccessToken(for: context.accountId) else { return }
        await viewModel.loadMessage(accessToken: token, messageId: context.messageId)
    }

    private func replyToMessage() {
        openWindow(id: "compose", value: UUID())
    }

    private func replyAllToMessage() {
        openWindow(id: "compose", value: UUID())
    }

    private func forwardMessage() {
        openWindow(id: "compose", value: UUID())
    }

    private func archiveMessage() async {
        actionInProgress = true
        guard let token = try? await mailboxVM.getAccessToken(for: context.accountId) else {
            actionInProgress = false
            return
        }
        let success = await viewModel.archiveMessage(accessToken: token)
        actionInProgress = false
        if success {
            dismiss()
        }
    }

    private func trashMessage() async {
        actionInProgress = true
        guard let token = try? await mailboxVM.getAccessToken(for: context.accountId) else {
            actionInProgress = false
            return
        }
        let success = await viewModel.trashMessage(accessToken: token)
        actionInProgress = false
        if success {
            dismiss()
        }
    }
}
