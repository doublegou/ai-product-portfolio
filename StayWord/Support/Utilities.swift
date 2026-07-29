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
            buttonStyle(
                LegacyFrostedButtonStyle(
                    shape: .capsule,
                    isProminent: true,
                    horizontalPadding: 16,
                    verticalPadding: 10,
                    minimumDimension: 44
                )
            )
        }
    }

}

struct LegacyFrostedButtonStyle: ButtonStyle {
    enum Shape {
        case circle
        case capsule
    }

    let shape: Shape
    var isProminent = false
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 8
    var minimumDimension: CGFloat = 44

    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            frostedContent(configuration)
                .foregroundStyle(.white)
        } else {
            frostedContent(configuration)
        }
    }

    private func frostedContent(_ configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: minimumDimension, minHeight: minimumDimension)
            .background {
                LegacyFrostedButtonBackground(
                    shape: shape,
                    isProminent: isProminent,
                    isPressed: configuration.isPressed
                )
            }
            .opacity(isEnabled ? 1 : 0.48)
    }
}

private struct LegacyFrostedButtonBackground: View {
    let shape: LegacyFrostedButtonStyle.Shape
    let isProminent: Bool
    let isPressed: Bool

    @ViewBuilder
    var body: some View {
        switch shape {
        case .circle:
            frostedLayers(in: Circle())
        case .capsule:
            frostedLayers(in: Capsule())
        }
    }

    private func frostedLayers<S: InsettableShape>(in shape: S) -> some View {
        shape
            .fill(.regularMaterial)
            .overlay {
                if isProminent {
                    shape.fill(
                        Color.accentColor.opacity(isPressed ? 0.78 : 0.68)
                    )
                } else if isPressed {
                    shape.fill(Color.primary.opacity(0.08))
                }
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(isPressed ? 0.18 : 0.12),
                    lineWidth: 0.5
                )
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
