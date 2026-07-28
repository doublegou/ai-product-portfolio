import SwiftData
import SwiftUI
import UIKit

private enum DetailTab: Hashable {
    case summary
    case transcript
    case edit
}

struct RecordingDetailView: View {
    let recordingID: UUID

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recordings: [AudioRecording]

    @State private var selectedTab: DetailTab = .summary
    @State private var lastContentTab: DetailTab = .summary
    @State private var showsEditor = false
    @State private var showsMoveSheet = false
    @State private var confirmsDelete = false
    @State private var playbackError: String?

    init(recordingID: UUID) {
        self.recordingID = recordingID
        _recordings = Query(
            filter: #Predicate<AudioRecording> { $0.id == recordingID }
        )
        Self.applyDetailTabBarTypography()
    }

    private var recording: AudioRecording? {
        recordings.first
    }

    var body: some View {
        Group {
            if let recording {
                detailTabs(recording)
            } else {
                ContentUnavailableView(
                    "Recording Not Found",
                    systemImage: "waveform.slash",
                    description: Text("This recording may have been deleted.")
                )
            }
        }
        .navigationTitle(recording?.title ?? String(localized: "Recording"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let recording {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = currentCopyText(for: recording)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .disabled(currentCopyText(for: recording).isEmpty)

                        Button {
                            recording.isFavorite.toggle()
                            services.save(modelContext)
                        } label: {
                            Label(
                                recording.isFavorite ? "Unfavorite" : "Favorite",
                                systemImage: recording.isFavorite ? "heart.slash" : "heart"
                            )
                        }

                        Button {
                            showsMoveSheet = true
                        } label: {
                            Label("Move", systemImage: "folder")
                        }

                        Button(role: .destructive) {
                            confirmsDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .labelStyle(.iconOnly)
                }

            }
        }
        .sheet(isPresented: $showsEditor) {
            if let recording {
                RecordingEditView(recording: recording)
            }
        }
        .sheet(isPresented: $showsMoveSheet) {
            if let recording {
                MoveRecordingsView(recordings: [recording]) {}
            }
        }
        .alert(
            "Delete selected recordings?",
            isPresented: $confirmsDelete
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteRecording()
            }
        } message: {
            Text("This recording will move to Recently Deleted.")
        }
        .alert(
            "Unable to Play",
            isPresented: Binding(
                get: { playbackError != nil },
                set: { if !$0 { playbackError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
        .onDisappear {
            services.player.stop()
            Self.restoreDefaultTabBarTypography()
        }
    }

    @ViewBuilder
    private func detailTabs(_ recording: AudioRecording) -> some View {
        if #available(iOS 26.0, *) {
            detailTabView(recording)
                .tabBarMinimizeBehavior(.never)
        } else {
            detailTabView(recording)
        }
    }

    private func detailTabView(_ recording: AudioRecording) -> some View {
        TabView(selection: $selectedTab) {
            Tab(value: DetailTab.summary) {
                detailForm(recording, content: .summary)
            } label: {
                Text("Summary")
            }

            Tab(value: DetailTab.transcript) {
                detailForm(recording, content: .transcript)
            } label: {
                Text("Transcript")
            }

            Tab(value: DetailTab.edit, role: .search) {
                detailForm(recording, content: lastContentTab)
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
        .background(DetailTabBarProbe())
        .onChange(of: selectedTab) { _, newValue in
            switch newValue {
            case .summary, .transcript:
                lastContentTab = newValue
            case .edit:
                showsEditor = true
                Task { @MainActor in
                    selectedTab = lastContentTab
                }
            }
        }
    }

    @ViewBuilder
    private func detailForm(
        _ recording: AudioRecording,
        content: DetailTab
    ) -> some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    HStack {
                        Text(
                            recording.createdAt,
                            format: .dateTime.year().month().day().hour().minute()
                        )
                        Spacer()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.72))

                    ScrubbableProgressView(
                        currentTime: services.player.currentTime,
                        duration: recording.duration,
                        onSeek: services.player.seek
                    )

                    HStack {
                        Text(services.player.currentTime.audioTimestamp)
                        Spacer()
                        Text("-\((recording.duration - services.player.currentTime).audioTimestamp)")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            services.player.skip(by: -15)
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back 15 Seconds")

                        Button {
                            preparePlayerIfNeeded(recording)
                            services.player.togglePlayback()
                        } label: {
                            Image(systemName: services.player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                                .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(services.player.isPlaying ? "Pause" : "Play")

                        Button {
                            services.player.skip(by: 15)
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Forward 15 Seconds")
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowInsets(
                    EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16)
                )
            }

            if recording.processingState.isProcessing {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading) {
                            Text(recording.processingState.localizedTitle)
                                .font(.headline)
                            Text("Audio and generated content stay on this device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            switch content {
            case .summary:
                summarySection(recording)
            case .transcript:
                transcriptSection(recording)
            case .edit:
                EmptyView()
            }

            if !recording.markers.isEmpty {
                Section("Markers") {
                    ForEach(recording.markers.sorted { $0.timestamp < $1.timestamp }) { marker in
                        Button {
                            preparePlayerIfNeeded(recording)
                            services.player.seek(to: marker.timestamp)
                        } label: {
                            Label(
                                marker.title.isEmpty ? String(localized: "Marker") : marker.title,
                                systemImage: "bookmark"
                            )
                            .badge(marker.timestamp.audioTimestamp)
                        }
                    }
                }
            }
        }
        .listSectionSpacing(12)
        .contentMargins(.top, 4, for: .scrollContent)
        .task {
            preparePlayerIfNeeded(recording)
        }
    }

    @ViewBuilder
    private func summarySection(_ recording: AudioRecording) -> some View {
        if recording.summaryText.isEmpty {
            Section {
                ContentUnavailableView {
                    Label {
                        Text("No Summary")
                    } icon: {
                        EmptyView()
                    }
                } description: {
                    Text(emptySummaryDescription(for: recording))
                } actions: {
                    if !recording.processingState.isProcessing {
                        retryButton(for: recording)
                    }
                }
            }
        } else {
            Section {
                HStack {
                    if !recording.summarySubject.isEmpty {
                        Text(recording.summarySubject)
                            .font(.headline)
                    }
                    Spacer()
                    summaryCopyButton(recording)
                }
                Text(recording.summaryText)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func transcriptSection(_ recording: AudioRecording) -> some View {
        let segments = recording.transcriptSegments.sorted { $0.startTime < $1.startTime }
        if segments.isEmpty {
            Section {
                HStack {
                    Text(recording.title)
                        .font(.headline)
                    Spacer()
                    transcriptCopyButton(recording)
                }
                ContentUnavailableView {
                    Label {
                        Text("No Transcript")
                    } icon: {
                        EmptyView()
                    }
                } description: {
                    Text(emptyTranscriptDescription(for: recording))
                } actions: {
                    if !recording.processingState.isProcessing {
                        retryButton(for: recording)
                    }
                }
            }
        } else {
            Section {
                HStack {
                    Text(recording.title)
                        .font(.headline)
                    Spacer()
                    transcriptCopyButton(recording)
                }
                ForEach(segments) { segment in
                    Button {
                        preparePlayerIfNeeded(recording)
                        services.player.seek(to: segment.startTime)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let speakerIndex = segment.speakerIndex {
                                Text(
                                    "Speaker \(speakerIndex + 1) · \(segment.startTime.audioTimestamp)"
                                )
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            } else {
                                Text(segment.startTime.audioTimestamp)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(segment.text)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Seeks audio to this transcript segment")
                }
            }
        }
    }

    private func summaryCopyButton(_ recording: AudioRecording) -> some View {
        Button {
            UIPasteboard.general.string = summaryCopyText(for: recording)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .accessibilityLabel("Copy Summary")
    }

    private func transcriptCopyButton(_ recording: AudioRecording) -> some View {
        Button {
            UIPasteboard.general.string = recording.transcriptText
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .disabled(recording.transcriptText.isEmpty)
        .accessibilityLabel("Copy Transcript")
    }

    private func preparePlayerIfNeeded(_ recording: AudioRecording) {
        do {
            try services.player.load(recording)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    private func emptySummaryDescription(for recording: AudioRecording) -> String {
        if let summaryFailureMessage = recording.summaryFailureMessage {
            return summaryFailureMessage
        }
        if recording.processingState == .failed {
            return recording.failureMessage
                ?? String(localized: "Try processing the recording again.")
        }
        return String(localized: "A summary will appear after transcription finishes.")
    }

    private func emptyTranscriptDescription(for recording: AudioRecording) -> String {
        if recording.processingState == .failed {
            return recording.failureMessage
                ?? String(localized: "Try processing the recording again.")
        }
        return String(localized: "A transcript will appear after processing finishes.")
    }

    private func retryButton(for recording: AudioRecording) -> some View {
        Button {
            services.processor.enqueue(recording, in: modelContext)
        } label: {
            Text("Retry")
                .frame(minWidth: 96)
        }
        .font(.title3.weight(.semibold))
        .controlSize(.large)
        .nativeProminentButtonStyle()
        .scaleEffect(0.94)
    }

    private func currentCopyText(for recording: AudioRecording) -> String {
        switch lastContentTab {
        case .summary:
            summaryCopyText(for: recording)
        case .transcript:
            recording.transcriptText
        case .edit:
            ""
        }
    }

    private func summaryCopyText(for recording: AudioRecording) -> String {
        [
            recording.summarySubject,
            recording.summaryText,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private func deleteRecording() {
        guard let recording else { return }
        services.player.stop()
        recording.deletedAt = .now
        if services.save(modelContext) {
            dismiss()
        }
    }

    private static func applyDetailTabBarTypography() {
        let itemAppearance = UITabBarItem.appearance()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .headline)
        ]

        itemAppearance.setTitleTextAttributes(attributes, for: .normal)
        itemAppearance.setTitleTextAttributes(attributes, for: .selected)
        itemAppearance.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -14)
    }

    private static func restoreDefaultTabBarTypography() {
        let itemAppearance = UITabBarItem.appearance()
        itemAppearance.setTitleTextAttributes(nil, for: .normal)
        itemAppearance.setTitleTextAttributes(nil, for: .selected)
        itemAppearance.titlePositionAdjustment = .zero
    }
}

private struct DetailTabBarProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.configureSoon()
    }

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureSoon()
        }

        fileprivate func configureSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.configureVisibleTabBar()
            }
        }

        private func configureVisibleTabBar() {
            guard let window else { return }

            let tabBars = visibleTabBars(in: window)
            guard let tabBar = tabBars.last,
                  let items = tabBar.items
            else {
                return
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .headline)
            ]

            for item in items.prefix(2) {
                item.setTitleTextAttributes(attributes, for: .normal)
                item.setTitleTextAttributes(attributes, for: .selected)
                item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -14)
            }

            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()

            tabBar.transform = .identity
            let bottomCenter = CGPoint(
                x: tabBar.frame.midX,
                y: tabBar.frame.maxY
            )
            tabBar.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            tabBar.layer.position = bottomCenter
            tabBar.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }

        private func visibleTabBars(in view: UIView) -> [UITabBar] {
            var result: [UITabBar] = []

            if let tabBar = view as? UITabBar,
               !tabBar.isHidden,
               tabBar.alpha > 0 {
                result.append(tabBar)
            }

            for subview in view.subviews {
                result.append(contentsOf: visibleTabBars(in: subview))
            }

            return result
        }
    }
}

private struct ScrubbableProgressView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isScrubbing = false

    private var safeDuration: TimeInterval {
        max(duration, 0.1)
    }

    private var clampedCurrentTime: TimeInterval {
        min(max(currentTime, 0), safeDuration)
    }

    var body: some View {
        GeometryReader { proxy in
            ProgressView(value: clampedCurrentTime, total: safeDuration)
                .progressViewStyle(.linear)
                .controlSize(.large)
                .tint(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(x: 1, y: isScrubbing ? 1.45 : 1)
                .animation(.snappy, value: isScrubbing)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let fraction = min(
                                max(value.location.x / max(proxy.size.width, 1), 0),
                                1
                            )
                            onSeek(max(duration, 0) * fraction)
                        }
                        .onEnded { _ in
                            isScrubbing = false
                        }
                )
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(clampedCurrentTime.audioTimestamp)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onSeek(min(currentTime + 5, max(duration, 0)))
            case .decrement:
                onSeek(max(currentTime - 5, 0))
            @unknown default:
                break
            }
        }
    }
}
