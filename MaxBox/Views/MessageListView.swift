import SwiftUI

struct MessageListView: View {
    @ObservedObject var viewModel: MessageListViewModel
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Filter toolbar
            HStack {
                Spacer()

                Button {
                    viewModel.filterUnread.toggle()
                } label: {
                    Image(systemName: viewModel.filterUnread ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.borderless)
                .help(viewModel.filterUnread ? "Show all messages" : "Show unread only")
                .foregroundStyle(viewModel.filterUnread ? .blue : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Message list
            if viewModel.filteredMessages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(emptyStateText)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                let showAccountBadge = mailboxVM.isMultiAccount && mailboxVM.selectedAccountId == nil
                List(selection: $viewModel.selectedMessageId) {
                    ForEach(viewModel.filteredMessages) { message in
                        MessageRowView(
                            message: message,
                            accountEmail: showAccountBadge ? mailboxVM.accountEmail(for: message.accountId ?? "") : nil
                        )
                        .contentShape(Rectangle())
                        .tag(message.id)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            let accountId = message.accountId ?? mailboxVM.selectedAccountId ?? ""
                            if message.isDraft {
                                openWindow(id: "compose-draft", value: DraftComposeContext(
                                    messageId: message.id,
                                    accountId: accountId
                                ))
                            } else {
                                openWindow(id: "message", value: MessageWindowContext(
                                    messageId: message.id,
                                    accountId: accountId
                                ))
                            }
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 350, max: 500)
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    private var emptyStateText: String {
        if mailboxVM.accounts.isEmpty {
            return "Add a Gmail account to view messages"
        }
        if viewModel.filterUnread {
            return "No unread messages"
        }
        return "No messages"
    }
}

struct MessageRowView: View {
    let message: Message
    var accountEmail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(message.isRead ? .clear : .blue)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            messageContent
        }
        .padding(.vertical, 4)
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.fromDisplay)
                    .font(.body)
                    .fontWeight(message.isRead ? .regular : .bold)
                    .lineLimit(1)

                Spacer()

                if message.isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Text(message.dateDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(message.subject)
                .font(.subheadline)
                .fontWeight(message.isRead ? .regular : .semibold)
                .lineLimit(1)

            HStack {
                Text(message.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let email = accountEmail {
                    Spacer()
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .opacity(message.isRead ? 0.85 : 1.0)
    }
}

#Preview {
    MessageListView(viewModel: MessageListViewModel())
        .environmentObject(MailboxViewModel())
}
