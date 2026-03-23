import Foundation

enum GmailAPIError: Error, LocalizedError {
    case notAuthenticated
    case requestFailed(Int, String)
    case decodingFailed(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated"
        case .requestFailed(let code, let message): return "API error \(code): \(message)"
        case .decodingFailed(let detail): return "Decoding failed: \(detail)"
        case .invalidURL: return "Invalid URL"
        }
    }
}

struct DraftResponse: Decodable {
    let id: String
}

struct DraftListResponse: Decodable {
    let drafts: [DraftEntry]?
}

struct DraftEntry: Decodable {
    let id: String
    let message: DraftMessageRef
}

struct DraftMessageRef: Decodable {
    let id: String
}

protocol GmailAPIServiceProtocol {
    func listMessages(accessToken: String, labelId: String, query: String?, pageToken: String?, maxResults: Int) async throws -> MessageListResponse
    func getMessage(accessToken: String, messageId: String) async throws -> Message
    func modifyMessage(accessToken: String, messageId: String, addLabels: [String], removeLabels: [String]) async throws
    func trashMessage(accessToken: String, messageId: String) async throws
    func archiveMessage(accessToken: String, messageId: String) async throws
    func sendMessage(accessToken: String, to: String, subject: String, body: String, cc: String?, bcc: String?) async throws
    func createDraft(accessToken: String, to: String, cc: String?, bcc: String?, subject: String, body: String) async throws -> String
    func updateDraft(accessToken: String, draftId: String, to: String, cc: String?, bcc: String?, subject: String, body: String) async throws
    func deleteDraft(accessToken: String, draftId: String) async throws
    func getDraftId(accessToken: String, messageId: String) async throws -> String?
}

final class GmailAPIService: GmailAPIServiceProtocol {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func listMessages(accessToken: String, labelId: String, query: String? = nil, pageToken: String? = nil, maxResults: Int = 50) async throws -> MessageListResponse {
        var components = URLComponents(string: "\(baseURL)/messages")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: "\(maxResults)")
        ]

        if !labelId.isEmpty {
            queryItems.append(URLQueryItem(name: "labelIds", value: labelId))
        }

        if let query = query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw GmailAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(MessageListResponse.self, from: data)
    }

    func getMessage(accessToken: String, messageId: String) async throws -> Message {
        let url = URL(string: "\(baseURL)/messages/\(messageId)?format=full")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let gmailMessage = try JSONDecoder().decode(GmailMessage.self, from: data)
        return parseGmailMessage(gmailMessage)
    }

    func modifyMessage(accessToken: String, messageId: String, addLabels: [String], removeLabels: [String]) async throws {
        let url = URL(string: "\(baseURL)/messages/\(messageId)/modify")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "addLabelIds": addLabels,
            "removeLabelIds": removeLabels
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    func trashMessage(accessToken: String, messageId: String) async throws {
        let url = URL(string: "\(baseURL)/messages/\(messageId)/trash")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    func archiveMessage(accessToken: String, messageId: String) async throws {
        try await modifyMessage(
            accessToken: accessToken,
            messageId: messageId,
            addLabels: [],
            removeLabels: ["INBOX"]
        )
    }

    func sendMessage(accessToken: String, to: String, subject: String, body: String, cc: String? = nil, bcc: String? = nil) async throws {
        let url = URL(string: "\(baseURL)/messages/send")!
        let encodedMessage = buildRawMessage(to: to, cc: cc, bcc: bcc, subject: subject, body: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["raw": encodedMessage]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    func createDraft(accessToken: String, to: String, cc: String?, bcc: String?, subject: String, body: String) async throws -> String {
        let url = URL(string: "\(baseURL)/drafts")!
        let encodedMessage = buildRawMessage(to: to, cc: cc, bcc: bcc, subject: subject, body: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["message": ["raw": encodedMessage]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let draft = try JSONDecoder().decode(DraftResponse.self, from: data)
        return draft.id
    }

    func updateDraft(accessToken: String, draftId: String, to: String, cc: String?, bcc: String?, subject: String, body: String) async throws {
        let url = URL(string: "\(baseURL)/drafts/\(draftId)")!
        let encodedMessage = buildRawMessage(to: to, cc: cc, bcc: bcc, subject: subject, body: body)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["message": ["raw": encodedMessage]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    func deleteDraft(accessToken: String, draftId: String) async throws {
        let url = URL(string: "\(baseURL)/drafts/\(draftId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    func getDraftId(accessToken: String, messageId: String) async throws -> String? {
        let url = URL(string: "\(baseURL)/drafts")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let listResponse = try JSONDecoder().decode(DraftListResponse.self, from: data)
        return listResponse.drafts?.first { $0.message.id == messageId }?.id
    }

    // MARK: - Private

    private func buildRawMessage(to: String, cc: String?, bcc: String? = nil, subject: String, body: String) -> String {
        var rawMessage = "To: \(to)\r\n"
        if let cc = cc, !cc.isEmpty {
            rawMessage += "Cc: \(cc)\r\n"
        }
        if let bcc = bcc, !bcc.isEmpty {
            rawMessage += "Bcc: \(bcc)\r\n"
        }
        rawMessage += "Subject: \(subject)\r\n"
        rawMessage += "Content-Type: text/plain; charset=utf-8\r\n"
        rawMessage += "\r\n"
        rawMessage += body

        return rawMessage.data(using: .utf8)!
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw GmailAPIError.requestFailed(httpResponse.statusCode, body)
        }
    }

    private func parseGmailMessage(_ gmail: GmailMessage) -> Message {
        let headers = gmail.payload?.headers ?? []
        let subject = headers.first { $0.name.lowercased() == "subject" }?.value ?? "(No Subject)"
        let from = headers.first { $0.name.lowercased() == "from" }?.value ?? ""
        let toHeader = headers.first { $0.name.lowercased() == "to" }?.value ?? ""
        let ccHeader = headers.first { $0.name.lowercased() == "cc" }?.value ?? ""
        let dateHeader = headers.first { $0.name.lowercased() == "date" }?.value

        let toAddresses = toHeader.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let ccAddresses = ccHeader.isEmpty ? [] : ccHeader.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let date: Date
        if let dateStr = dateHeader {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            date = formatter.date(from: dateStr) ?? Date()
        } else if let internalDate = gmail.internalDate, let ms = Double(internalDate) {
            date = Date(timeIntervalSince1970: ms / 1000)
        } else {
            date = Date()
        }

        let bodyContent = extractBody(from: gmail.payload)
        let labels = gmail.labelIds ?? []
        let isRead = !labels.contains("UNREAD")
        let isStarred = labels.contains("STARRED")

        return Message(
            id: gmail.id,
            threadId: gmail.threadId,
            subject: subject,
            from: from,
            to: toAddresses,
            cc: ccAddresses,
            date: date,
            snippet: gmail.snippet ?? "",
            body: bodyContent.plainText,
            bodyHTML: bodyContent.html,
            isRead: isRead,
            isStarred: isStarred,
            labelIds: labels
        )
    }

    private func extractBody(from payload: GmailPayload?) -> (plainText: String, html: String?) {
        guard let payload = payload else { return ("", nil) }

        var plainText: String?
        var html: String?

        // Single-part message
        if payload.mimeType == "text/plain", let data = payload.body?.data {
            return (decodeBase64URL(data), nil)
        }
        if payload.mimeType == "text/html", let data = payload.body?.data {
            let decoded = decodeBase64URL(data)
            return ("", decoded)
        }

        // Multi-part: collect both plain and HTML
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/plain", let data = part.body?.data, plainText == nil {
                    plainText = decodeBase64URL(data)
                }
                if part.mimeType == "text/html", let data = part.body?.data, html == nil {
                    html = decodeBase64URL(data)
                }
            }
            // Check nested parts (e.g. multipart/alternative inside multipart/mixed)
            if plainText == nil || html == nil {
                for part in parts {
                    if let nestedParts = part.parts {
                        for nested in nestedParts {
                            if nested.mimeType == "text/plain", let data = nested.body?.data, plainText == nil {
                                plainText = decodeBase64URL(data)
                            }
                            if nested.mimeType == "text/html", let data = nested.body?.data, html == nil {
                                html = decodeBase64URL(data)
                            }
                        }
                    }
                }
            }
        }

        return (plainText ?? "", html)
    }

    private func decodeBase64URL(_ encoded: String) -> String {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
