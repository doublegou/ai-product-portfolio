import Foundation
import SwiftUI
import UIKit

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

    @ViewBuilder
    func adaptiveToolbarCircleButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            buttonStyle(
                LegacyFrostedButtonStyle(
                    shape: .circle,
                    horizontalPadding: 12,
                    verticalPadding: 12
                )
            )
        }
    }

    @ViewBuilder
    func legacyFrostedToolbarCapsuleLabel() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    LegacyFrostedButtonBackground(
                        shape: .capsule,
                        isProminent: false,
                        isPressed: false
                    )
                }
                .contentShape(Capsule())
        }
    }

    @ViewBuilder
    func legacyNavigationBackButtonHidden() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            navigationBarBackButtonHidden(true)
                .background(LegacyNavigationPopGestureRestorer())
        }
    }

}

struct AdaptiveToolbarButtonIcon: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 20, height: 20)
                .accessibilityLabel(title)
        }
    }
}

struct AdaptiveToolbarMenuIcon: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.primary.opacity(0.12),
                            lineWidth: 0.5
                        )
                }
                .contentShape(Circle())
                .accessibilityLabel(title)
        }
    }
}

struct AdaptiveMenuAction: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let systemImage: String
    var role: ButtonRole?
    var isEnabled: Bool
    var accessibilityIdentifier: String?
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isEnabled = isEnabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }
}

struct AdaptiveOverflowMenu<LabelContent: View>: View {
    let actions: [AdaptiveMenuAction]
    private let label: () -> LabelContent

    @State private var isPresented = false

    init(
        actions: [AdaptiveMenuAction],
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        self.actions = actions
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            Menu {
                ForEach(actions) { action in
                    nativeButton(for: action)
                }
            } label: {
                label()
            }
        } else {
            Button {
                isPresented = true
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                LegacyOverflowMenu(actions: actions) { action in
                    isPresented = false
                    Task { @MainActor in
                        await Task.yield()
                        action.action()
                    }
                }
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    @ViewBuilder
    private func nativeButton(for action: AdaptiveMenuAction) -> some View {
        Button(role: action.role, action: action.action) {
            Label(action.title, systemImage: action.systemImage)
        }
        .disabled(!action.isEnabled)
        .optionalAccessibilityIdentifier(action.accessibilityIdentifier)
    }
}

private struct LegacyOverflowMenu: View {
    let actions: [AdaptiveMenuAction]
    let perform: (AdaptiveMenuAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Divider()
                        .padding(.leading, 42)
                }

                Button(role: action.role) {
                    perform(action)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.systemImage)
                            .font(.body.weight(.medium))
                            .frame(width: 20, alignment: .center)

                        Text(action.title)
                            .font(.body)

                        Spacer(minLength: 4)
                    }
                    .frame(minWidth: 156, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    action.role == .destructive ? Color.red : Color.primary
                )
                .disabled(!action.isEnabled)
                .opacity(action.isEnabled ? 1 : 0.4)
                .optionalAccessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
        .padding(6)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct LegacyNavigationBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(
            LegacyFrostedButtonStyle(
                shape: .circle,
                horizontalPadding: 12,
                verticalPadding: 12
            )
        )
        .accessibilityLabel("Back")
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
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

private struct LegacyNavigationPopGestureRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.restoreGestureSoon()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreGestureSoon()
        }

        fileprivate func restoreGestureSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let navigationController = self?.navigationController,
                      navigationController.viewControllers.count > 1,
                      let gesture = navigationController.interactivePopGestureRecognizer
                else { return }

                gesture.delegate = nil
                gesture.isEnabled = true
            }
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
        .accessibilityIdentifier("record-button")
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
