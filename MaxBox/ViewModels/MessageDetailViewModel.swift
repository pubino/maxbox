import Foundation

@MainActor
final class MessageDetailViewModel: ObservableObject {
    @Published var message: Message?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let gmailService: GmailAPIServiceProtocol

    init(gmailService: GmailAPIServiceProtocol? = nil) {
        self.gmailService = gmailService ?? GmailAPIService()
    }

    func loadMessage(accessToken: String, messageId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            message = try await gmailService.getMessage(accessToken: accessToken, messageId: messageId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func archiveMessage(accessToken: String) async -> Bool {
        guard let messageId = message?.id else { return false }

        do {
            try await gmailService.archiveMessage(accessToken: accessToken, messageId: messageId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func trashMessage(accessToken: String) async -> Bool {
        guard let messageId = message?.id else { return false }

        do {
            try await gmailService.trashMessage(accessToken: accessToken, messageId: messageId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
