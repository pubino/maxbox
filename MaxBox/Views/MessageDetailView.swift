import SwiftUI

struct MessageDetailView: View {
    @ObservedObject var viewModel: MessageDetailViewModel
    @EnvironmentObject var mailboxVM: MailboxViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading...")
            } else if let message = viewModel.message {
                messageContent(message)
            } else {
                ContentUnavailableView(
                    "No Message Selected",
                    systemImage: "envelope",
                    description: Text("Select a message to view its contents.")
                )
            }
        }
        .frame(minWidth: 400)
    }

    @ViewBuilder
    private func messageContent(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar with archive and trash
            HStack {
                Spacer()

                Button {
                    Task { await archiveMessage() }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .buttonStyle(.borderless)
                .help("Archive message")

                Button {
                    Task { await trashMessage() }
                } label: {
                    Label("Trash", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Move to trash")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Subject
                    Text(message.subject)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)

                    // From / To / Date
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("From:")
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Text(message.from)
                                .textSelection(.enabled)
                        }

                        HStack(alignment: .top) {
                            Text("To:")
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Text(message.to.joined(separator: ", "))
                                .textSelection(.enabled)
                        }

                        if !message.cc.isEmpty {
                            HStack(alignment: .top) {
                                Text("Cc:")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                                Text(message.cc.joined(separator: ", "))
                                    .textSelection(.enabled)
                            }
                        }

                        HStack {
                            Text("Date:")
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            Text(message.date, style: .date)
                            Text(message.date, style: .time)
                        }
                    }
                    .font(.subheadline)

                    Divider()

                    // Body
                    Text(message.body.isEmpty ? message.snippet : message.body)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
        }
    }

    private func archiveMessage() async {
        guard let token = await getAccessToken() else { return }
        let success = await viewModel.archiveMessage(accessToken: token)
        if success {
            viewModel.message = nil
        }
    }

    private func trashMessage() async {
        guard let token = await getAccessToken() else { return }
        let success = await viewModel.trashMessage(accessToken: token)
        if success {
            viewModel.message = nil
        }
    }

    private func getAccessToken() async -> String? {
        guard let account = mailboxVM.activeAccounts.first else { return nil }
        return try? await mailboxVM.getAccessToken(for: account.id)
    }
}

#Preview {
    MessageDetailView(viewModel: MessageDetailViewModel())
        .environmentObject(MailboxViewModel())
}
