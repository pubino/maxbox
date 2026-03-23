import SwiftUI

struct MessageDetailView: View {
    @ObservedObject var viewModel: MessageDetailViewModel
    @AppStorage("loadRemoteImages") private var loadRemoteImages = false
    @State private var loadImagesForCurrentMessage = false

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
        .onChange(of: viewModel.message?.id) {
            loadImagesForCurrentMessage = false
        }
    }

    private var shouldLoadImages: Bool {
        loadRemoteImages || loadImagesForCurrentMessage
    }

    @ViewBuilder
    private func messageContent(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if message.hasHTML {
                VStack(alignment: .leading, spacing: 0) {
                    messageHeader(message)
                        .padding(16)

                    Divider()

                    if !shouldLoadImages && message.hasRemoteImages {
                        remoteImagesBanner
                    }

                    HTMLContentView(html: message.bodyHTML!, allowRemoteImages: shouldLoadImages)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        messageHeader(message)

                        Divider()

                        Text(message.body.isEmpty ? message.snippet : message.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var remoteImagesBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("Remote images are hidden.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Load Images") {
                loadImagesForCurrentMessage = true
            }
            .buttonStyle(.borderless)
            .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary)
    }

    @ViewBuilder
    private func messageHeader(_ message: Message) -> some View {
        // Subject
        HStack(alignment: .top, spacing: 8) {
            if !message.isRead {
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
            }
            Text(message.subject)
                .font(.title2)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }

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
    }

}

#Preview {
    MessageDetailView(viewModel: MessageDetailViewModel())
        .environmentObject(MailboxViewModel())
}
