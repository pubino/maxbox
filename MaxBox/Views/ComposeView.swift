import SwiftUI
import AppKit

struct ComposeView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ComposeViewModel()
    @State private var pendingCloseAction: CloseAction?
    @State private var showBcc = false

    var draftContext: DraftComposeContext?
    var composeContext: ComposeContext?

    private enum CloseAction {
        case saveDraft, discard
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fields
            Form {
                TextField("To:", text: $viewModel.to)
                    .textFieldStyle(.plain)

                TextField("Cc:", text: $viewModel.cc)
                    .textFieldStyle(.plain)

                if showBcc {
                    TextField("Bcc:", text: $viewModel.bcc)
                        .textFieldStyle(.plain)
                }

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
        .focusedSceneValue(\.showBcc, $showBcc)
        .background(WindowCloseInterceptor {
            viewModel.requestClose()
        })
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let savedAt = viewModel.draftSavedAt {
                    Text("Draft saved \(savedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .blue)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.isValid || viewModel.isSending)
                .help("Send")
            }
        }
        .alert("Unsaved Draft", isPresented: $viewModel.showCloseConfirmation) {
            Button("Save as Draft") {
                pendingCloseAction = .saveDraft
            }
            Button("Discard", role: .destructive) {
                pendingCloseAction = .discard
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have an unsaved message. What would you like to do?")
        }
        .onChange(of: pendingCloseAction) {
            guard let action = pendingCloseAction else { return }
            pendingCloseAction = nil
            Task {
                switch action {
                case .saveDraft:
                    await viewModel.saveDraft()
                    viewModel.stopAutoSave()
                case .discard:
                    await viewModel.discardDraft()
                }
                dismiss()
            }
        }
        .onAppear {
            resolveAccessToken()
        }
        .onChange(of: viewModel.didSend) {
            if viewModel.didSend {
                dismiss()
            }
        }
    }

    private func resolveAccessToken() {
        Task {
            let accountId: String?
            if let ctx = draftContext {
                accountId = ctx.accountId
            } else if let ctx = composeContext {
                accountId = ctx.accountId
            } else {
                accountId = mailboxVM.selectedAccountId ?? mailboxVM.activeAccounts.first?.id
            }
            guard let id = accountId,
                  let token = try? await mailboxVM.getAccessToken(for: id) else {
                return
            }
            viewModel.accessToken = token

            if let ctx = draftContext {
                await viewModel.loadDraft(accessToken: token, messageId: ctx.messageId)
            } else if let ctx = composeContext {
                viewModel.populateFromContext(ctx)
            }

            viewModel.startAutoSave()
        }
    }

    private func send() async {
        let accountId = mailboxVM.selectedAccountId ?? mailboxVM.activeAccounts.first?.id
        guard let id = accountId,
              let token = try? await mailboxVM.getAccessToken(for: id) else {
            viewModel.errorMessage = "No authenticated account. Please sign in first."
            return
        }
        await viewModel.send(accessToken: token)
    }
}

// MARK: - Window Close Interceptor

/// Intercepts the native window close (red button / Cmd+W) to allow the
/// compose view model to show a confirmation alert before closing.
private struct WindowCloseInterceptor: NSViewRepresentable {
    var shouldClose: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.install(on: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldClose = shouldClose
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldClose: shouldClose)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool
        private weak var originalDelegate: (any NSWindowDelegate)?
        private weak var window: NSWindow?

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
        }

        func install(on window: NSWindow) {
            guard self.window == nil else { return }
            self.window = window
            self.originalDelegate = window.delegate
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldClose()
        }

        // Forward all other delegate messages to SwiftUI's original delegate.
        override func responds(to aSelector: Selector!) -> Bool {
            if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
                return true
            }
            return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let original = originalDelegate, original.responds(to: aSelector) {
                return original
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}
