import SwiftUI

struct ComposeView: View {
    @Binding var isPresented: Bool
    @ObservedObject var mailboxVM: MailboxViewModel
    @StateObject private var viewModel = ComposeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("New Message")
                    .font(.headline)

                Spacer()

                Button("Send") {
                    Task { await send() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.isValid || viewModel.isSending)
            }
            .padding()

            Divider()

            // Fields
            Form {
                TextField("To:", text: $viewModel.to)
                    .textFieldStyle(.plain)

                TextField("Cc:", text: $viewModel.cc)
                    .textFieldStyle(.plain)

                TextField("Subject:", text: $viewModel.subject)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Body
            TextEditor(text: $viewModel.body)
                .font(.body)
                .padding(8)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if viewModel.isSending {
                ProgressView()
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onChange(of: viewModel.didSend) {
            if viewModel.didSend {
                isPresented = false
            }
        }
    }

    private func send() async {
        guard let account = mailboxVM.activeAccounts.first,
              let token = try? await mailboxVM.getAccessToken(for: account.id) else {
            viewModel.errorMessage = "No authenticated account. Please sign in first."
            return
        }
        await viewModel.send(accessToken: token)
    }
}
