import SwiftUI

@main
struct MaxBoxApp: App {
    @StateObject private var mailboxViewModel = MailboxViewModel()
    @StateObject private var activityManager = ActivityManager.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(mailboxViewModel)
                .environmentObject(activityManager)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenComposeButton()
                    .environmentObject(mailboxViewModel)

                NewWindowButton()

                Divider()

                Button("Add Account...") {
                    mailboxViewModel.showAddAccountDialog = true
                }
            }
            CommandGroup(after: .windowList) {
                OpenActivityWindowButton()
            }
            CommandGroup(after: .toolbar) {
                ToggleBCCMenuItem()
            }
        }

        WindowGroup("New Message", id: "compose", for: UUID.self) { _ in
            ComposeView()
                .environmentObject(mailboxViewModel)
        }
        .defaultSize(width: 560, height: 480)

        WindowGroup("Draft", id: "compose-draft", for: DraftComposeContext.self) { $context in
            if let context {
                ComposeView(draftContext: context)
                    .environmentObject(mailboxViewModel)
            }
        }
        .defaultSize(width: 560, height: 480)

        WindowGroup("Reply", id: "compose-reply", for: ComposeContext.self) { $context in
            if let context {
                ComposeView(composeContext: context)
                    .environmentObject(mailboxViewModel)
            }
        }
        .defaultSize(width: 560, height: 480)

        WindowGroup("Message", id: "message", for: MessageWindowContext.self) { $context in
            if let context {
                MessageWindowView(context: context)
                    .environmentObject(mailboxViewModel)
            }
        }
        .defaultSize(width: 700, height: 600)

        Window("Activity", id: "activity") {
            ActivityView()
                .environmentObject(activityManager)
        }
        .defaultSize(width: 400, height: 500)

        Settings {
            SettingsView()
                .environmentObject(mailboxViewModel)
        }
    }
}

// MARK: - Menu Buttons

private struct OpenComposeButton: View {
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var mailboxVM: MailboxViewModel

    var body: some View {
        Button("New Message") {
            openWindow(id: "compose", value: UUID())
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(mailboxVM.activeAccounts.isEmpty)
    }
}

private struct NewWindowButton: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "main")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}

private struct OpenActivityWindowButton: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("Activity") {
            openWindow(id: "activity")
        }
        .keyboardShortcut("0", modifiers: [.command, .option])
    }
}

private struct ToggleBCCMenuItem: View {
    @FocusedValue(\.showBcc) var showBcc

    var body: some View {
        Button(showBcc?.wrappedValue == true ? "Hide BCC Field" : "Show BCC Field") {
            showBcc?.wrappedValue.toggle()
        }
        .keyboardShortcut("b", modifiers: [.command, .option])
        .disabled(showBcc == nil)
    }
}

// MARK: - Focused Values

struct ShowBccKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showBcc: Binding<Bool>? {
        get { self[ShowBccKey.self] }
        set { self[ShowBccKey.self] = newValue }
    }
}
