import SwiftUI

struct RecordingRow: View {
    let recording: AudioRecording

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(
                        recording.createdAt,
                        format: .dateTime
                            .month(.abbreviated)
                            .day()
                            .year()
                    )

                    if recording.processingState == .failed {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Processing Failed")
                    } else if recording.processingState.isOverallProcessing {
                        PersistentActivityIndicator()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                            .accessibilityLabel(recording.processingState.localizedTitle)
                    } else if !recording.transcriptSegments.isEmpty {
                        Image(systemName: "quote.bubble")
                            .accessibilityLabel("Transcript available")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(recording.duration.audioTimestamp)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
