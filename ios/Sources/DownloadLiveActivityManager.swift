import ActivityKit
import Foundation

@MainActor
final class DownloadLiveActivityManager {
    static let shared = DownloadLiveActivityManager()

    private var activity: Activity<DownloadActivityAttributes>?

    private init() {}

    func start(aid: String, title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            update(progress: 0, status: "准备下载…")
            return
        }

        let attributes = DownloadActivityAttributes(title: title, aid: aid)
        for existing in Activity<DownloadActivityAttributes>.activities {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }
        let content = ActivityContent(
            state: DownloadActivityAttributes.ContentState(
                progress: 0, status: "准备下载…"
            ),
            staleDate: Date().addingTimeInterval(120)
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    func update(progress: Double, status: String) {
        guard let activity else { return }
        let value = min(1, max(0, progress))
        let content = ActivityContent(
            state: DownloadActivityAttributes.ContentState(
                progress: value, status: status
            ),
            staleDate: Date().addingTimeInterval(120)
        )
        Task {
            await activity.update(content)
        }
    }

    func end(progress: Double, status: String) {
        guard let activity else { return }
        self.activity = nil
        let value = min(1, max(0, progress))
        let content = ActivityContent(
            state: DownloadActivityAttributes.ContentState(
                progress: value, status: status
            ),
            staleDate: nil
        )
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
