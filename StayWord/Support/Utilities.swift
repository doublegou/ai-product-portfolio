import Foundation
import SwiftUI

enum StayWordError: LocalizedError {
    case microphoneDenied
    case recordingUnavailable
    case invalidAudioFile
    case fileCopyFailed
    case onDeviceSpeechUnavailable
    case emptyTranscript
    case recordingNotFound

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            String(localized: "Microphone access is required to record audio.")
        case .recordingUnavailable:
            String(localized: "Audio recording is currently unavailable.")
        case .invalidAudioFile:
            String(localized: "The selected file is not a supported audio file.")
        case .fileCopyFailed:
            String(localized: "The audio file could not be copied into StayWord.")
        case .onDeviceSpeechUnavailable:
            String(localized: "On-device transcription is not available for the current language.")
        case .emptyTranscript:
            String(localized: "No speech was detected in this recording.")
        case .recordingNotFound:
            String(localized: "The recording file could not be found.")
        }
    }
}

extension View {
    @ViewBuilder
    func nativeProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

}

struct NativeRecordButton: View {
    let action: () -> Void
    @State private var feedbackTrigger = false

    var body: some View {
        Button {
            feedbackTrigger.toggle()
            action()
        } label: {
            ZStack {
                recordButtonGlass

                Circle()
                    .fill(.red)
                    .padding(4)
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .frame(minWidth: 64, minHeight: 64)
        .sensoryFeedback(.impact(weight: .medium), trigger: feedbackTrigger)
        .accessibilityLabel("Record")
        .accessibilityHint("Starts a new audio recording")
    }

    @ViewBuilder
    private var recordButtonGlass: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(.regularMaterial)
        }
    }
}
