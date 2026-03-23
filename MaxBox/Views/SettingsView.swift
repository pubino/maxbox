import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel

    var body: some View {
        TabView {
            AccountsSettingsView()
                .tabItem {
                    Label("Accounts", systemImage: "person.2.fill")
                }

            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct PrivacySettingsView: View {
    @AppStorage("loadRemoteImages") private var loadRemoteImages = false

    var body: some View {
        Form {
            Toggle("Load Remote Images Automatically", isOn: $loadRemoteImages)
                .help("When disabled, remote images in messages will not be loaded until you choose to load them.")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AccountsSettingsView: View {
    @EnvironmentObject var mailboxVM: MailboxViewModel
    @State private var accountToRemove: Account?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mailboxVM.accounts.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No accounts configured")
                        .font(.headline)
                    Text("Add a Gmail account to start using MaxBox.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add Account...") {
                        Task { await mailboxVM.addAccount() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mailboxVM.isSigningIn)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(mailboxVM.accounts) { account in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { account.isActive },
                                set: { _ in mailboxVM.toggleAccountActive(account) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.body)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Remove") {
                                accountToRemove = account
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                HStack {
                    Button {
                        Task { await mailboxVM.addAccount() }
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .disabled(mailboxVM.isSigningIn)

                    if mailboxVM.isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                        Button("Cancel") {
                            mailboxVM.cancelSignIn()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    Spacer()
                }
                .padding(12)
            }
        }
        .alert("Remove Account", isPresented: Binding(
            get: { accountToRemove != nil },
            set: { if !$0 { accountToRemove = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                accountToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let account = accountToRemove {
                    Task { await mailboxVM.removeAccount(account) }
                    accountToRemove = nil
                }
            }
        } message: {
            if let account = accountToRemove {
                Text("Are you sure you want to remove \(account.email)?")
            }
        }
        .alert("Authentication Error", isPresented: Binding(
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
    SettingsView()
        .environmentObject(MailboxViewModel())
}
