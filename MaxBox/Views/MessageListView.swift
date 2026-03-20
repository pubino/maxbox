import SwiftUI

struct MessageListView: View {
    @ObservedObject var viewModel: MessageListViewModel
    @EnvironmentObject var mailboxVM: MailboxViewModel
    var onComposeClicked: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with compose and filter
            HStack {
                Button(action: onComposeClicked) {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("Compose new message")

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
            if viewModel.isLoading && viewModel.messages.isEmpty {
                Spacer()
                ProgressView("Loading messages...")
                Spacer()
            } else if viewModel.filteredMessages.isEmpty {
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
                List(selection: $viewModel.selectedMessageId) {
                    ForEach(viewModel.filteredMessages) { message in
                        MessageRowView(message: message)
                            .tag(message.id)
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

    var body: some View {
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

            Text(message.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .opacity(message.isRead ? 0.85 : 1.0)
    }
}

#Preview {
    MessageListView(
        viewModel: MessageListViewModel(),
        onComposeClicked: {}
    )
    .environmentObject(MailboxViewModel())
}
