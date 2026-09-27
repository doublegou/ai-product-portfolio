import SwiftUI

struct RecordingSheet: View {
    let onFinished: (RecordedAudio, String) -> Bool

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var startsAutomatically = true
    @State private var isFinishing = false
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var recordingTitle = RecordingTitleProvider().suggestedTitle()
    @State private var pendingResult: RecordedAudio?
    @FocusState private var titleIsFocused: Bool

    private var recorder: AudioRecorderController {
        services.recorder
    }

    var body: some View {
        GeometryReader { proxy in
            let isExpanded = proxy.size.height > 520

            VStack(spacing: 12) {
                TextField("Recording Title", text: $recordingTitle)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .multilineTextAlignment(isExpanded ? .center : .leading)
                    .focused($titleIsFocused)
                    .accessibilityIdentifier("recorder-title")
                    .frame(
                        maxWidth: .infinity,
                        alignment: isExpanded ? .center : .leading
                    )
                    .onSubmit {
                        normalizeTitle()
                    }

                if !isExpanded {
                    recordingTimer(expanded: false)
                }

                AudioWaveformView(
                    samples: recorder.amplitudes,
                    activeColor: recorder.isPaused ? .secondary : .red,
                    inactiveColor: .red
                )
                .frame(maxWidth: .infinity)
                .frame(height: isExpanded ? min(280, proxy.size.height * 0.32) : 104)

                if isExpanded {
                    recordingTimer(expanded: true)
                }

                if let interruptionMessage = recorder.interruptionMessage {
                    Label(interruptionMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 4)

                if isExpanded {
                    expandedControlRow
                } else {
                    finishButton
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
        .interactiveDismissDisabled(recorder.isRecording || pendingResult != nil)
        .task {
            guard startsAutomatically, !recorder.isRecording else { return }
            startsAutomatically = false
            do {
                try await recorder.start(title: recordingTitle)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: recorder.needsFinishingAfterFailure) { _, needsFinishing in
            guard needsFinishing else { return }
            recorder.acknowledgeFinishingAfterFailure()
            finishRecording()
        }
        .alert(
            "Unable to Record",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("Close", role: .cancel) {
                dismiss()
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Couldn't Save the Recording",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var finishButton: some View {
        if #available(iOS 26.0, *) {
            finishButtonControl
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
        } else {
            finishButtonControl
                .buttonStyle(
                    LegacyFrostedButtonStyle(
                        shape: .circle,
                        horizontalPadding: 12,
                        verticalPadding: 12,
                        minimumDimension: 48
                    )
                )
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
        }
    }

    private var finishButtonControl: some View {
        Button {
            finishRecording()
        } label: {
            Group {
                if isFinishing {
                    ProgressView()
                } else {
                    Label("Stop Recording", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(.red)
        }
        .disabled((!recorder.isRecording && pendingResult == nil) || isFinishing)
        .accessibilityHint("Stops and saves this recording")
        .accessibilityIdentifier("recorder-stop")
    }

    private func recordingTimer(expanded: Bool) -> some View {
        Text(recorder.elapsed.recordingTimestamp)
            .font(expanded ? .largeTitle.monospacedDigit() : .title3.monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Recording time")
            .accessibilityValue(recorder.elapsed.recordingTimestamp)
    }

    @ViewBuilder
    private var expandedControlRow: some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 16) {
                pauseButton
                    .buttonStyle(.glass)
                    .controlSize(.large)

                finishButtonControl
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
            }
        } else {
            HStack(spacing: 16) {
                pauseButton
                    .buttonStyle(
                        LegacyFrostedButtonStyle(
                            shape: .capsule,
                            horizontalPadding: 16,
                            verticalPadding: 10
                        )
                    )
                    .controlSize(.large)

                finishButtonControl
                    .buttonStyle(
                        LegacyFrostedButtonStyle(
                            shape: .circle,
                            horizontalPadding: 12,
                            verticalPadding: 12,
                            minimumDimension: 48
                        )
                    )
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
            }
        }
    }

    private var pauseButton: some View {
        Button {
            if recorder.isPaused {
                recorder.resume()
            } else {
                recorder.pause()
            }
        } label: {
            ZStack {
                Label("Pause", systemImage: "pause.fill")
                    .hidden()
                Label("Resume", systemImage: "play.fill")
                    .hidden()
                Label(
                    recorder.isPaused ? "Resume" : "Pause",
                    systemImage: recorder.isPaused ? "play.fill" : "pause.fill"
                )
            }
        }
        .sensoryFeedback(.selection, trigger: recorder.isPaused)
        .accessibilityIdentifier("recorder-pause-resume")
    }

    private func finishRecording() {
        if let pendingResult {
            normalizeTitle()
            if onFinished(pendingResult, recordingTitle) {
                self.pendingResult = nil
            } else {
                presentSaveError()
            }
            return
        }

        isFinishing = true
        Task {
            do {
                let result = try await recorder.finish()
                isFinishing = false
                normalizeTitle()
                if !onFinished(result, recordingTitle) {
                    pendingResult = result
                    presentSaveError()
                }
            } catch {
                isFinishing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func normalizeTitle() {
        let trimmed = recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        recordingTitle = trimmed.isEmpty
            ? services.recordingTitleProvider.suggestedTitle()
            : trimmed
        titleIsFocused = false
    }

    private func presentSaveError() {
        saveErrorMessage = services.operationErrorMessage
            ?? String(localized: "The recording wasn't saved. Your audio is still available on this screen.")
        services.operationErrorMessage = nil
    }
}
