import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "record.circle.fill")
                    .font(.title2)
                    .foregroundStyle(context.state.isPaused ? Color.secondary : Color.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                    recordingTimer(context: context)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.isPaused ? "Paused" : "Recording")
                    .font(.caption)
                    .foregroundStyle(context.state.isPaused ? Color.secondary : Color.red)
            }
            .padding()
            .activityBackgroundTint(.clear)
            .widgetURL(URL(string: "stayword://recording/active"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    recordingTimer(context: context)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isPaused ? "Recording Paused" : context.attributes.title)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "record.circle.fill")
                    .foregroundStyle(context.state.isPaused ? Color.secondary : Color.red)
            } compactTrailing: {
                recordingTimer(context: context)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
            }
            .widgetURL(URL(string: "stayword://recording/active"))
        }
    }

    @ViewBuilder
    private func recordingTimer(
        context: ActivityViewContext<RecordingActivityAttributes>
    ) -> some View {
        if context.state.isPaused {
            Text(context.state.elapsedAtPause.audioTimestamp)
        } else {
            let timerStart = context.state.runningSince.addingTimeInterval(
                -context.state.elapsedAtPause
            )
            Text(
                timerInterval: timerStart...Date.distantFuture,
                countsDown: false,
                showsHours: true
            )
        }
    }
}
