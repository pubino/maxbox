import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var activityManager: ActivityManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                if activityManager.activities.contains(where: { !$0.isActive }) {
                    Button("Clear") {
                        activityManager.clearCompleted()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding()

            Divider()

            if activityManager.activities.isEmpty {
                Spacer()
                Text("No recent activity")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(activityManager.recentActivities) { activity in
                        ActivityRowView(activity: activity)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 350, minHeight: 300)
    }
}

struct ActivityRowView: View {
    let activity: MailActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusIcon
                Text(activity.title)
                    .font(.body)
                Spacer()
                timestampText
            }

            if let detail = activity.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if activity.isActive {
                if let progress = activity.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch activity.status {
        case .inProgress:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
                .font(.caption)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private var timestampText: some View {
        Group {
            if let completed = activity.completedAt {
                Text(completed, style: .relative)
            } else {
                Text(activity.startedAt, style: .relative)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}

#Preview {
    ActivityView()
        .environmentObject(ActivityManager.shared)
}
