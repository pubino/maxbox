import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel

    var body: some View {
        List(selection: $mailboxVM.selectedMailboxType) {
            if mailboxVM.accounts.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "envelope.badge")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Accounts")
                            .font(.headline)
                        Text("Add a Gmail account to get started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            // Unified mailboxes (or per-account)
            Section("Mailboxes") {
                ForEach(MailboxType.allCases) { type in
                    Label(type.displayName, systemImage: type.systemImage)
                        .tag(type)
                }
            }

            // Accounts section
            Section("Accounts") {
                if mailboxVM.accounts.isEmpty {
                    Text("No accounts configured")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(mailboxVM.accounts) { account in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(account.displayName)
                                    .font(.body)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Remove Account", role: .destructive) {
                                Task { await mailboxVM.removeAccount(account) }
                            }
                        }
                    }
                }

                Button {
                    Task { await mailboxVM.addAccount() }
                } label: {
                    Label("Add Account", systemImage: "plus.circle")
                }
                .disabled(mailboxVM.isSigningIn)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .alert("Authentication Error", isPresented: .init(
            get: { mailboxVM.authError != nil },
            set: { if !$0 { mailboxVM.authError = nil } }
        )) {
            Button("OK") { mailboxVM.authError = nil }
        } message: {
            Text(mailboxVM.authError ?? "")
        }
    }
}

#Preview {
    SidebarView()
        .environmentObject(MailboxViewModel())
}
