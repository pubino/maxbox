import Foundation

@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var to = ""
    @Published var cc = ""
    @Published var subject = ""
    @Published var body = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var didSend = false

    private let gmailService: GmailAPIServiceProtocol

    init(gmailService: GmailAPIServiceProtocol? = nil) {
        self.gmailService = gmailService ?? GmailAPIService()
    }

    var isValid: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty &&
        !subject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func send(accessToken: String) async {
        guard isValid else {
            errorMessage = "Please fill in the To and Subject fields."
            return
        }

        isSending = true
        errorMessage = nil

        do {
            try await gmailService.sendMessage(
                accessToken: accessToken,
                to: to,
                subject: subject,
                body: body,
                cc: cc.isEmpty ? nil : cc
            )
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    func reset() {
        to = ""
        cc = ""
        subject = ""
        body = ""
        errorMessage = nil
        didSend = false
    }
}
