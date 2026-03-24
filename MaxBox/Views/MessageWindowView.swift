import SwiftUI

struct MessageWindowView: View {
    let context: MessageWindowContext
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MessageDetailViewModel()
    @State private var actionInProgress = false
    @State private var showTrashConfirmation = false
    @State private var showArchiveConfirmation = false

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

                    Button { showArchiveConfirmation = true } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .help("Archive")
                    .disabled(viewModel.message == nil || actionInProgress)

                    Button { showTrashConfirmation = true } label: {
                        Label("Trash", systemImage: "trash")
                    }
                    .help("Move to trash")
                    .disabled(viewModel.message == nil || actionInProgress)
                }
            }
            .onAppear {
                Task { await loadMessage() }
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
    }

    private func loadMessage() async {
        guard let token = try? await mailboxVM.getAccessToken(for: context.accountId) else { return }
        await viewModel.loadMessage(accessToken: token, messageId: context.messageId)
    }

    private func buildComposeContext(mode: ComposeMode) -> ComposeContext? {
        guard let message = viewModel.message else { return nil }
        return ComposeContext(
            mode: mode,
            accountId: context.accountId,
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
