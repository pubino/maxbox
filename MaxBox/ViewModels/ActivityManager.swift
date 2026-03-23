import Foundation

@MainActor
final class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published private(set) var activities: [MailActivity] = []

    var currentActivity: MailActivity? {
        activities.first(where: \.isActive)
    }

    var hasActiveWork: Bool {
        activities.contains(where: \.isActive)
    }

    var recentActivities: [MailActivity] {
        let active = activities.filter(\.isActive)
        let completed = activities.filter { !$0.isActive }.prefix(50)
        return active + completed
    }

    @discardableResult
    func start(_ title: String, total: Int? = nil) -> UUID {
        let activity = MailActivity(title: title, total: total)
        activities.insert(activity, at: 0)
        pruneOldActivities()
        return activity.id
    }

    func update(_ id: UUID, current: Int, total: Int? = nil, detail: String? = nil) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].current = current
        if let total { activities[index].total = total }
        if let detail { activities[index].detail = detail }
    }

    func complete(_ id: UUID) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].status = .completed
        activities[index].completedAt = Date()
        if let total = activities[index].total {
            activities[index].current = total
        }
    }

    func fail(_ id: UUID, error: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].status = .failed(error)
        activities[index].completedAt = Date()
    }

    func clearCompleted() {
        activities.removeAll { !$0.isActive }
    }

    private func pruneOldActivities() {
        let cutoff = Date().addingTimeInterval(-3600)
        activities.removeAll { !$0.isActive && ($0.completedAt ?? .distantFuture) < cutoff }
    }
}
