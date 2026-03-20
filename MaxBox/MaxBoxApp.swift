import SwiftUI

@main
struct MaxBoxApp: App {
    @StateObject private var mailboxViewModel = MailboxViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mailboxViewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
