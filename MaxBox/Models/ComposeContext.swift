import Foundation

enum ComposeMode: String, Codable {
    case reply
    case replyAll
    case forward
}

struct ComposeContext: Codable, Hashable {
    let mode: ComposeMode
    let accountId: String
    let originalFrom: String
    let originalTo: [String]
    let originalCc: [String]
    let originalSubject: String
    let originalDate: Date
    let originalBody: String
    let originalBodyHTML: String?
}
