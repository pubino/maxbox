import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @EnvironmentObject var activityManager: ActivityManager
    @State private var expandedMailboxes: Set<MailboxType> = [.inbox]

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { mailboxVM.selection },
                set: { if let v = $0 { mailboxVM.selection = v } }
            )) {
                if mailboxVM.accounts.isEmpty {
                    Section {
                        Text("No Accounts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Mailboxes") {
                        if mailboxVM.isMultiAccount {
                            multiAccountMailboxes
                        } else {
                            singleAccountMailboxes
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            // Activity indicator at bottom of sidebar
            if let activity = activityManager.currentActivity {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    if let progress = activity.progress {
                        ProgressView(value: progress)
                            .controlSize(.small)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(activity.detail ?? activity.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activityManager.hasActiveWork)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }

    // MARK: - Single Account (flat list)

    @ViewBuilder
    private var singleAccountMailboxes: some View {
        ForEach(MailboxType.allCases) { type in
            Label(type.displayName, systemImage: type.systemImage)
                .tag(SidebarSelection.allAccounts(type))
        }
    }

    // MARK: - Multi Account (disclosure groups)

    @ViewBuilder
    private var multiAccountMailboxes: some View {
        ForEach(MailboxType.allCases) { type in
            DisclosureGroup(isExpanded: Binding(
                get: { expandedMailboxes.contains(type) },
                set: { isExpanded in
                    if isExpanded {
                        expandedMailboxes.insert(type)
                    } else {
                        expandedMailboxes.remove(type)
                    }
                }
            )) {
                ForEach(mailboxVM.activeAccounts) { account in
                    Label(account.email, systemImage: "person.crop.circle")
                        .font(.subheadline)
                        .tag(SidebarSelection.account(type, accountId: account.id))
                }
            } label: {
                Label(type.displayName, systemImage: type.systemImage)
                    .tag(SidebarSelection.allAccounts(type))
            }
        }
    }
}

#Preview {
    SidebarView()
        .environmentObject(MailboxViewModel())
        .environmentObject(ActivityManager.shared)
}
