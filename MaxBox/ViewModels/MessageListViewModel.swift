import Foundation
import Combine

@MainActor
final class MessageListViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var selectedMessageId: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var filterUnread = false

    private let gmailService: GmailAPIServiceProtocol
    private var nextPageToken: String?
    private var hasMorePages = true

    var filteredMessages: [Message] {
        if filterUnread {
            return messages.filter { !$0.isRead }
        }
        return messages
    }

    var selectedMessage: Message? {
        messages.first { $0.id == selectedMessageId }
    }

    init(gmailService: GmailAPIServiceProtocol? = nil) {
        self.gmailService = gmailService ?? GmailAPIService()
    }

    func loadMessages(accessToken: String, labelId: String, query: String? = nil) async {
        isLoading = true
        errorMessage = nil
        nextPageToken = nil
        hasMorePages = true

        do {
            let searchQ = buildQuery(query)
            let response = try await gmailService.listMessages(
                accessToken: accessToken,
                labelId: labelId,
                query: searchQ,
                pageToken: nil,
                maxResults: 50
            )

            nextPageToken = response.nextPageToken
            hasMorePages = response.nextPageToken != nil

            guard let refs = response.messages else {
                messages = []
                isLoading = false
                return
            }

            // Fetch full message details
            var loadedMessages: [Message] = []
            for ref in refs {
                do {
                    let message = try await gmailService.getMessage(
                        accessToken: accessToken,
                        messageId: ref.id
                    )
                    loadedMessages.append(message)
                } catch {
                    // Skip individual message failures
                }
            }

            messages = loadedMessages
        } catch {
            errorMessage = error.localizedDescription
            messages = []
        }

        isLoading = false
    }

    func loadMoreMessages(accessToken: String, labelId: String) async {
        guard hasMorePages, let pageToken = nextPageToken, !isLoading else { return }

        isLoading = true

        do {
            let response = try await gmailService.listMessages(
                accessToken: accessToken,
                labelId: labelId,
                query: buildQuery(nil),
                pageToken: pageToken,
                maxResults: 50
            )

            nextPageToken = response.nextPageToken
            hasMorePages = response.nextPageToken != nil

            guard let refs = response.messages else {
                isLoading = false
                return
            }

            for ref in refs {
                do {
                    let message = try await gmailService.getMessage(
                        accessToken: accessToken,
                        messageId: ref.id
                    )
                    messages.append(message)
                } catch {
                    // Skip
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func markAsRead(accessToken: String, messageId: String) async {
        do {
            try await gmailService.modifyMessage(
                accessToken: accessToken,
                messageId: messageId,
                addLabels: [],
                removeLabels: ["UNREAD"]
            )
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index].isRead = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleStar(accessToken: String, messageId: String) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        let isStarred = messages[index].isStarred
        do {
            try await gmailService.modifyMessage(
                accessToken: accessToken,
                messageId: messageId,
                addLabels: isStarred ? [] : ["STARRED"],
                removeLabels: isStarred ? ["STARRED"] : []
            )
            messages[index].isStarred = !isStarred
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildQuery(_ additionalQuery: String?) -> String? {
        var parts: [String] = []
        if !searchQuery.isEmpty {
            parts.append(searchQuery)
        }
        if let additional = additionalQuery, !additional.isEmpty {
            parts.append(additional)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
