import ActivityKit
import Foundation

private final class RecordingActivityHandle: @unchecked Sendable {
    let value: Activity<RecordingActivityAttributes>

    init(_ value: Activity<RecordingActivityAttributes>) {
        self.value = value
    }

    func update(_ content: ActivityContent<RecordingActivityAttributes.ContentState>) async {
        await value.update(content)
    }

    func end(_ content: ActivityContent<RecordingActivityAttributes.ContentState>) async {
        await value.end(content, dismissalPolicy: .immediate)
    }
}

actor RecordingLiveActivityService {
    private var activity: RecordingActivityHandle?
    private var startedAt = Date.now

    func start(recordingID: UUID, title: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        startedAt = .now
        let attributes = RecordingActivityAttributes(
            recordingID: recordingID,
            title: title,
            startedAt: startedAt
        )
        let state = RecordingActivityAttributes.ContentState(
            isPaused: false,
            elapsedAtPause: 0,
            runningSince: startedAt
        )

        do {
            activity = RecordingActivityHandle(
                try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            )
        } catch {
            activity = nil
        }
    }

    func update(isPaused: Bool, elapsed: TimeInterval) async {
        guard let activity else { return }
        let state = RecordingActivityAttributes.ContentState(
            isPaused: isPaused,
            elapsedAtPause: elapsed,
            runningSince: .now
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        guard let activity else { return }
        let elapsed = max(0, Date.now.timeIntervalSince(startedAt))
        let state = RecordingActivityAttributes.ContentState(
            isPaused: true,
            elapsedAtPause: elapsed,
            runningSince: .now
        )
        await activity.end(ActivityContent(state: state, staleDate: nil))
        self.activity = nil
    }
}
