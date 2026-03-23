import Foundation

struct MailActivity: Identifiable, Equatable {
    let id: UUID
    var title: String
    var detail: String?
    var current: Int
    var total: Int?
    var status: Status
    var startedAt: Date
    var completedAt: Date?

    enum Status: Equatable {
        case inProgress
        case completed
        case failed(String)
    }

    var isActive: Bool {
        if case .inProgress = status { return true }
        return false
    }

    var progress: Double? {
        guard let total, total > 0 else { return nil }
        return Double(current) / Double(total)
    }

    init(id: UUID = UUID(), title: String, detail: String? = nil, current: Int = 0, total: Int? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.current = current
        self.total = total
        self.status = .inProgress
        self.startedAt = Date()
    }
}
