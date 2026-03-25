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
            CommandMenu("Message") {
                MessageMenuItem(label: "Reply", shortcut: "r", modifiers: .command) { $0.reply }
                MessageMenuItem(label: "Reply All", shortcut: "r", modifiers: [.command, .shift]) { $0.replyAll }
                MessageMenuItem(label: "Forward", shortcut: "f", modifiers: [.command, .shift]) { $0.forward }
                Divider()
                MessageMenuItem(label: "Archive", shortcut: "e", modifiers: .command) { $0.archive }
                MessageMenuItem(label: "Delete", shortcut: .delete, modifiers: .command) { $0.trash }
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

private struct MessageMenuItem: View {
    let label: String
    let shortcut: KeyEquivalent
    let modifiers: EventModifiers
    let action: (MessageActions) -> (() -> Void)?

    @FocusedValue(\.messageActions) var messageActions

    var body: some View {
        Button(label) {
            if let actions = messageActions {
                action(actions)?()
            }
        }
        .keyboardShortcut(shortcut, modifiers: modifiers)
        .disabled(messageActions == nil || action(messageActions!) == nil)
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

struct MessageActions {
    var reply: (() -> Void)?
    var replyAll: (() -> Void)?
    var forward: (() -> Void)?
    var archive: (() -> Void)?
    var trash: (() -> Void)?
}

struct MessageActionsKey: FocusedValueKey {
    typealias Value = MessageActions
}

extension FocusedValues {
    var showBcc: Binding<Bool>? {
        get { self[ShowBccKey.self] }
        set { self[ShowBccKey.self] = newValue }
    }

    var messageActions: MessageActions? {
        get { self[MessageActionsKey.self] }
        set { self[MessageActionsKey.self] = newValue }
    }
}
