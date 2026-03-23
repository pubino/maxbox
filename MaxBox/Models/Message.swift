import Foundation

struct Message: Identifiable, Hashable, Codable {
    let id: String
    let threadId: String
    var subject: String
    var from: String
    var to: [String]
    var cc: [String]
    var date: Date
    var snippet: String
    var body: String
    var bodyHTML: String?
    var isRead: Bool
    var isStarred: Bool
    var labelIds: [String]
    var accountId: String?

    var fromDisplay: String {
        // Extract display name or email
        if let angleBracket = from.firstIndex(of: "<") {
            return String(from[from.startIndex..<angleBracket]).trimmingCharacters(in: .whitespaces)
        }
        return from
    }

    var dateDisplay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    var hasHTML: Bool {
        bodyHTML != nil && !(bodyHTML?.isEmpty ?? true)
    }

    var isDraft: Bool {
        labelIds.contains("DRAFT")
    }

    var hasRemoteImages: Bool {
        guard let html = bodyHTML else { return false }
        let pattern = #"<img[^>]+src\s*=\s*["']https?://"#
        return html.range(of: pattern, options: .regularExpression) != nil
    }

    static let placeholder = Message(
        id: "",
        threadId: "",
        subject: "",
        from: "",
        to: [],
        cc: [],
        date: Date(),
        snippet: "",
        body: "",
        isRead: true,
        isStarred: false,
        labelIds: []
    )
}

struct MessageListResponse: Decodable {
    let messages: [MessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct MessageRef: Decodable {
    let id: String
    let threadId: String
}

struct GmailMessage: Decodable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: GmailPayload?
    let internalDate: String?
}

struct GmailPayload: Decodable {
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailPart]?
    let mimeType: String?
}

struct GmailHeader: Decodable {
    let name: String
    let value: String
}

struct GmailBody: Decodable {
    let size: Int?
    let data: String?
}

struct GmailPart: Decodable {
    let mimeType: String?
    let body: GmailBody?
    let parts: [GmailPart]?
}
