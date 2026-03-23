import Foundation

enum SidebarSelection: Hashable, Codable {
    case allAccounts(MailboxType)
    case account(MailboxType, accountId: String)

    var mailboxType: MailboxType {
        switch self {
        case .allAccounts(let type): return type
        case .account(let type, _): return type
        }
    }

    var accountId: String? {
        switch self {
        case .allAccounts: return nil
        case .account(_, let id): return id
        }
    }

    var cacheKey: String {
        switch self {
        case .allAccounts(let type):
            return "allAccounts_\(type.rawValue)"
        case .account(let type, let id):
            return "account_\(id)_\(type.rawValue)"
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind, mailboxType, accountId
    }

    private enum Kind: String, Codable {
        case allAccounts, account
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let type = try container.decode(MailboxType.self, forKey: .mailboxType)
        switch kind {
        case .allAccounts:
            self = .allAccounts(type)
        case .account:
            let id = try container.decode(String.self, forKey: .accountId)
            self = .account(type, accountId: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allAccounts(let type):
            try container.encode(Kind.allAccounts, forKey: .kind)
            try container.encode(type, forKey: .mailboxType)
        case .account(let type, let id):
            try container.encode(Kind.account, forKey: .kind)
            try container.encode(type, forKey: .mailboxType)
            try container.encode(id, forKey: .accountId)
        }
    }
}

enum MailboxType: String, CaseIterable, Identifiable, Codable, Hashable {
    case inbox = "INBOX"
    case starred = "STARRED"
    case drafts = "DRAFT"
    case sent = "SENT"
    case allMail = "ALL_MAIL"
    case spam = "SPAM"
    case trash = "TRASH"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .starred: return "Starred"
        case .drafts: return "Drafts"
        case .sent: return "Sent"
        case .allMail: return "All Mail"
        case .spam: return "Spam"
        case .trash: return "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.fill"
        case .starred: return "star.fill"
        case .drafts: return "doc.fill"
        case .sent: return "paperplane.fill"
        case .allMail: return "tray.2.fill"
        case .spam: return "exclamationmark.shield.fill"
        case .trash: return "trash.fill"
        }
    }

    var gmailLabelId: String {
        switch self {
        case .inbox: return "INBOX"
        case .starred: return "STARRED"
        case .drafts: return "DRAFT"
        case .sent: return "SENT"
        case .allMail: return ""  // No label filter for all mail
        case .spam: return "SPAM"
        case .trash: return "TRASH"
        }
    }
}

struct Mailbox: Identifiable, Hashable {
    let id: String
    let type: MailboxType
    let accountId: String
    var unreadCount: Int

    init(type: MailboxType, accountId: String, unreadCount: Int = 0) {
        self.id = "\(accountId)_\(type.rawValue)"
        self.type = type
        self.accountId = accountId
        self.unreadCount = unreadCount
    }
}
