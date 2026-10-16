import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPaused: Bool
        var elapsedAtPause: TimeInterval
        var runningSince: Date
    }

    var recordingID: UUID
    var title: String
    var startedAt: Date
}
