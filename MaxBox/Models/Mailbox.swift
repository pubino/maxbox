import Foundation

enum MailboxType: String, CaseIterable, Identifiable, Codable {
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
