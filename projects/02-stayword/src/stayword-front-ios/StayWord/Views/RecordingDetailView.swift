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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var recordings: [AudioRecording]

    @State private var selectedTab: DetailTab = .summary
    @State private var lastContentTab: DetailTab = .summary
    @State private var showsEditor = false
    @State private var showsMoveSheet = false
    @State private var confirmsDelete = false
    @State private var playbackError: String?
    @State private var shareError: String?
    @State private var isPreparingShare = false
    @State private var showsShareChoices = false
    @State private var preparedExport: PreparedRecordingExport?
    @State private var followsTranscriptPlayback = true

    init(recordingID: UUID) {
        self.recordingID = recordingID
        _recordings = Query(
            filter: #Predicate<AudioRecording> { $0.id == recordingID }
        )
        if #available(iOS 26.0, *) {
            Self.applyDetailTabBarTypography()
        }
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
        .legacyNavigationBackButtonHidden()
        .toolbar {
            if let recording {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        detailShareMenu(recording)
                    }

                    ToolbarSpacer(.fixed, placement: .topBarTrailing)

                    ToolbarItem(placement: .topBarTrailing) {
                        detailActionsMenu(recording)
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        LegacyNavigationBackButton {
                            dismiss()
                        }
                        .accessibilityIdentifier("detail-back")
                    }

                    ToolbarItem(placement: .principal) {
                        Text(recording.title)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        detailShareMenu(recording)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        detailActionsMenu(recording)
                    }
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
        .sheet(item: $preparedExport, onDismiss: cleanupPreparedExport) { export in
            SystemShareView(itemURL: export.fileURL) {
                services.exporter.cleanup(export)
                preparedExport = nil
            }
            .ignoresSafeArea()
        }
        .alert(
            "Share",
            isPresented: $showsShareChoices
        ) {
            if let recording {
                shareChoiceButtons(recording)
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Delete selected recordings?",
            isPresented: $confirmsDelete
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteRecording()
            }
            .accessibilityIdentifier("detail-confirm-delete")
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
        .alert(
            "Unable to Share",
            isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .onDisappear {
            services.player.stop()
            if #available(iOS 26.0, *) {
                Self.restoreDefaultTabBarTypography()
            }
        }
    }

    @ViewBuilder
    private func detailTabs(_ recording: AudioRecording) -> some View {
        if #available(iOS 26.0, *) {
            detailTabView(recording)
                .tabBarMinimizeBehavior(.never)
        } else {
            legacyDetailView(recording)
        }
    }

    private func legacyDetailView(_ recording: AudioRecording) -> some View {
        detailForm(recording, content: lastContentTab)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                legacyDetailBar
                    .offset(y: 10)
            }
    }

    private func detailTabView(_ recording: AudioRecording) -> some View {
        TabView(selection: $selectedTab) {
            Tab(value: DetailTab.summary) {
                detailForm(recording, content: .summary)
            } label: {
                Text("Summary")
                    .accessibilityIdentifier("detail-summary-tab")
            }

            Tab(value: DetailTab.transcript) {
                detailForm(recording, content: .transcript)
            } label: {
                Text("Transcript")
                    .accessibilityIdentifier("detail-transcript-tab")
            }

            Tab(value: DetailTab.edit, role: .search) {
                detailForm(recording, content: lastContentTab)
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
                    .accessibilityIdentifier("detail-edit")
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

    private var legacyDetailBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                legacyTabButton("Summary", tab: .summary)
                legacyTabButton("Transcript", tab: .transcript)
            }
            .padding(4)
            .frame(maxWidth: 252)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }

            Spacer(minLength: 0)

            Button {
                showsEditor = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title2.weight(.medium))
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(
                LegacyFrostedButtonStyle(
                    shape: .circle,
                    horizontalPadding: 0,
                    verticalPadding: 0,
                    minimumDimension: 64
                )
            )
            .accessibilityLabel("Edit")
            .accessibilityIdentifier("detail-edit")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func legacyTabButton(
        _ title: LocalizedStringKey,
        tab: DetailTab
    ) -> some View {
        let isSelected = lastContentTab == tab

        return Button {
            let animation: Animation? = reduceMotion
                ? nil
                : .snappy(duration: 0.2)
            withAnimation(animation) {
                selectedTab = tab
                lastContentTab = tab
            }
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .transition(.opacity)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            tab == .summary ? "detail-summary-tab" : "detail-transcript-tab"
        )
    }

    @ViewBuilder
    private func detailActionsMenu(_ recording: AudioRecording) -> some View {
        if #available(iOS 26.0, *) {
            Menu {
                Button {
                    Task { @MainActor in
                        await Task.yield()
                        showsShareChoices = true
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(isPreparingShare)
                .accessibilityIdentifier("detail-share-action")

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
                .accessibilityIdentifier("detail-move")

                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("detail-delete")
            } label: {
                AdaptiveToolbarMenuIcon(
                    "More",
                    systemImage: "ellipsis"
                )
            }
            .accessibilityIdentifier("detail-more")
        } else {
            AdaptiveOverflowMenu(actions: [
                AdaptiveMenuAction(
                    "Share",
                    systemImage: "square.and.arrow.up",
                    isEnabled: !isPreparingShare,
                    accessibilityIdentifier: "detail-share-action"
                ) {
                    showsShareChoices = true
                },
                AdaptiveMenuAction(
                    recording.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: recording.isFavorite ? "heart.slash" : "heart"
                ) {
                    recording.isFavorite.toggle()
                    services.save(modelContext)
                },
                AdaptiveMenuAction(
                    "Move",
                    systemImage: "folder",
                    accessibilityIdentifier: "detail-move"
                ) {
                    showsMoveSheet = true
                },
                AdaptiveMenuAction(
                    "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    accessibilityIdentifier: "detail-delete"
                ) {
                    confirmsDelete = true
                }
            ]) {
                AdaptiveToolbarMenuIcon(
                    "More",
                    systemImage: "ellipsis"
                )
            }
            .accessibilityIdentifier("detail-more")
        }
    }

    private func detailShareMenu(_ recording: AudioRecording) -> some View {
        Menu {
            shareChoiceButtons(recording)
        } label: {
            ZStack {
                AdaptiveToolbarMenuIcon(
                    "Share",
                    systemImage: "square.and.arrow.up"
                )
                .opacity(isPreparingShare ? 0 : 1)

                if isPreparingShare {
                    ProgressView()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Preparing Share")
                }
            }
        }
        .disabled(isPreparingShare)
        .accessibilityIdentifier("detail-share")
    }

    @ViewBuilder
    private func shareChoiceButtons(_ recording: AudioRecording) -> some View {
        let snapshot = services.exporter.snapshot(for: recording)

        Button {
            prepareExport(.audio, from: snapshot)
        } label: {
            Label("Share Audio", systemImage: "waveform")
        }
        .disabled(!services.exporter.isAvailable(.audio, in: snapshot))
        .accessibilityIdentifier("detail-share-audio")

        Button {
            prepareExport(.transcript, from: snapshot)
        } label: {
            Label("Share Transcript", systemImage: "text.document")
        }
        .disabled(!services.exporter.isAvailable(.transcript, in: snapshot))
        .accessibilityIdentifier("detail-share-transcript")

        Button {
            prepareExport(.summary, from: snapshot)
        } label: {
            Label("Share Summary", systemImage: "text.page")
        }
        .disabled(!services.exporter.isAvailable(.summary, in: snapshot))
        .accessibilityIdentifier("detail-share-summary")
    }

    @ViewBuilder
    private func detailForm(
        _ recording: AudioRecording,
        content: DetailTab
    ) -> some View {
        let activeTranscriptSegmentID = content == .transcript
            ? TranscriptPlaybackSync.activeSegmentID(
                in: recording.transcriptSegments,
                at: services.player.currentTime
            )
            : nil

        ScrollViewReader { scrollProxy in
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
                        onSeek: { time in
                            followsTranscriptPlayback = true
                            services.player.seek(to: time)
                        }
                    )

                    HStack {
                        Text(services.player.currentTime.audioTimestamp)
                        Spacer()
                        Text("-\((recording.duration - services.player.currentTime).audioTimestamp)")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                    ZStack(alignment: .trailing) {
                        HStack(spacing: 12) {
                            Button {
                                followsTranscriptPlayback = true
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
                                if !services.player.isPlaying {
                                    followsTranscriptPlayback = true
                                }
                                services.player.togglePlayback()
                            } label: {
                                Image(systemName: services.player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.largeTitle)
                                    .frame(width: 56, height: 56)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(services.player.isPlaying ? "Pause" : "Play")

                            Button {
                                followsTranscriptPlayback = true
                                services.player.skip(by: 15)
                            } label: {
                                Image(systemName: "goforward.15")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Forward 15 Seconds")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        PlaybackRateControl(player: services.player)
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowInsets(
                    EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16)
                )
            }

            if content == .summary,
               recording.processingState.isOverallProcessing {
                Section {
                    HStack(spacing: 12) {
                        PersistentActivityIndicator()
                        VStack(alignment: .leading) {
                            Text(recording.processingState.localizedTitle)
                                .font(.headline)
                            Text("Audio and generated content stay on this device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("detail-processing-status")
                }
            }

            if content == .transcript,
               recording.processingState.isTranscriptionProcessing {
                Section {
                    HStack(spacing: 12) {
                        PersistentActivityIndicator()
                        VStack(alignment: .leading) {
                            Text(recording.processingState.localizedTitle)
                                .font(.headline)
                            Text("Audio and generated content stay on this device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("detail-transcription-status")
                }
            }

            switch content {
            case .summary:
                summarySection(recording)
            case .transcript:
                transcriptSection(
                    recording,
                    activeSegmentID: activeTranscriptSegmentID
                )
            case .edit:
                EmptyView()
            }

            if !recording.markers.isEmpty {
                Section("Markers") {
                    ForEach(recording.markers.sorted { $0.timestamp < $1.timestamp }) { marker in
                        Button {
                            preparePlayerIfNeeded(recording)
                            followsTranscriptPlayback = true
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
            .onScrollPhaseChange { _, newPhase in
                guard
                    content == .transcript,
                    newPhase == .interacting
                else { return }
                followsTranscriptPlayback = false
            }
            .onChange(of: activeTranscriptSegmentID) { _, newID in
                guard content == .transcript, followsTranscriptPlayback else {
                    return
                }
                scrollToTranscriptSegment(newID, using: scrollProxy)
            }
            .onChange(of: selectedTab) { _, newTab in
                guard
                    content == .transcript,
                    newTab == .transcript,
                    followsTranscriptPlayback
                else { return }
                scrollToTranscriptSegment(
                    activeTranscriptSegmentID,
                    using: scrollProxy
                )
            }
            .overlay(alignment: .topTrailing) {
                if content == .transcript,
                   !followsTranscriptPlayback,
                   services.player.isPlaying,
                   let activeTranscriptSegmentID {
                    Button {
                        followsTranscriptPlayback = true
                        scrollToTranscriptSegment(
                            activeTranscriptSegmentID,
                            using: scrollProxy
                        )
                    } label: {
                        Label("Follow Playback", systemImage: "scope")
                            .labelStyle(.iconOnly)
                            .frame(width: 28, height: 28)
                    }
                    .buttonBorderShape(.circle)
                    .tint(.primary)
                    .followPlaybackButtonStyle()
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .accessibilityHint("Scrolls to the current transcript segment")
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.2),
                value: followsTranscriptPlayback
            )
            .task {
                preparePlayerIfNeeded(recording)
                guard content == .transcript, followsTranscriptPlayback else {
                    return
                }
                await Task.yield()
                scrollToTranscriptSegment(
                    activeTranscriptSegmentID,
                    using: scrollProxy
                )
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ recording: AudioRecording) -> some View {
        let summarySubject = SummaryMarkupCleaner.clean(recording.summarySubject)
        let summaryText = SummaryMarkupCleaner.clean(recording.summaryText)

        if summaryText.isEmpty {
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
                    if !recording.processingState.isOverallProcessing {
                        retryButton(for: recording)
                    }
                }
            }
        } else {
            Section {
                HStack {
                    if !summarySubject.isEmpty {
                        Text(summarySubject)
                            .font(.headline)
                    }
                    Spacer()
                    summaryCopyButton(recording)
                }
                Text(summaryText)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func transcriptSection(
        _ recording: AudioRecording,
        activeSegmentID: UUID?
    ) -> some View {
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
                    if !recording.processingState.isOverallProcessing {
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
                .listRowSeparator(.hidden)
                ForEach(segments) { segment in
                    let isActive = segment.id == activeSegmentID
                    Button {
                        preparePlayerIfNeeded(recording)
                        followsTranscriptPlayback = true
                        services.player.seek(to: segment.startTime)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(segment.startTime.audioTimestamp)
                                Spacer()
                                if isActive {
                                    Image(systemName: "waveform")
                                        .accessibilityHidden(true)
                                }
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                isActive ? Color.accentColor : Color.secondary
                            )
                            Text(segment.text)
                                .foregroundStyle(
                                    isActive ? Color.accentColor : Color.primary
                                )
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .id(segment.id)
                    .accessibilityIdentifier("transcript-segment-\(segment.id.uuidString)")
                    .listRowInsets(
                        EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
                    )
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                    .accessibilityValue(
                        isActive ? Text("Currently Playing") : Text("")
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.2),
                        value: isActive
                    )
                    .accessibilityHint("Seeks audio to this transcript segment")
                }
            }
        }
    }

    private func scrollToTranscriptSegment(
        _ segmentID: UUID?,
        using proxy: ScrollViewProxy
    ) {
        guard let segmentID else { return }
        if reduceMotion {
            proxy.scrollTo(segmentID, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(segmentID, anchor: .center)
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

    private func prepareExport(
        _ kind: RecordingExportKind,
        from snapshot: RecordingExportSnapshot
    ) {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            do {
                preparedExport = try await services.exporter.prepare(
                    kind,
                    from: snapshot
                )
            } catch {
                shareError = error.localizedDescription
            }
        }
    }

    private func cleanupPreparedExport() {
        guard let preparedExport else { return }
        services.exporter.cleanup(preparedExport)
        self.preparedExport = nil
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
        .accessibilityIdentifier("detail-retry")
    }

    private func summaryCopyText(for recording: AudioRecording) -> String {
        [
            SummaryMarkupCleaner.clean(recording.summarySubject),
            SummaryMarkupCleaner.clean(recording.summaryText),
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

@MainActor
private struct PlaybackRateControl: View {
    @Bindable var player: AudioPlayerController

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(AudioPlayerController.playbackRateLabel(player.playbackRate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 48, height: 44, alignment: .trailing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transaction { transaction in
                    transaction.animation = nil
                }

            Menu {
                ForEach(player.supportedPlaybackRates, id: \.self) { rate in
                    Button(
                        AudioPlayerController.playbackRateLabel(rate)
                    ) {
                        player.setPlaybackRate(rate)
                    }
                }
            } label: {
                Color.clear
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            } primaryAction: {
                player.cyclePlaybackRate()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback Speed")
            .accessibilityValue(
                AudioPlayerController.playbackRateLabel(player.playbackRate)
            )
            .accessibilityHint(
                "Tap to change speed. Touch and hold for all speeds."
            )
            .accessibilityIdentifier("playback-speed")
        }
    }
}

private struct SystemShareView: UIViewControllerRepresentable {
    let itemURL: URL
    let onCompletion: @MainActor @Sendable () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [itemURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                onCompletion()
            }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private extension View {
    @ViewBuilder
    func followPlaybackButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(
                LegacyFrostedButtonStyle(
                    shape: .circle,
                    horizontalPadding: 8,
                    verticalPadding: 8
                )
            )
        }
    }
}

enum TranscriptPlaybackSync {
    static func activeSegmentID(
        in segments: [TranscriptSegment],
        at playbackTime: TimeInterval
    ) -> UUID? {
        guard playbackTime.isFinite, playbackTime >= 0 else { return nil }

        let ordered = segments.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                lhs.sortOrder < rhs.sortOrder
            } else {
                lhs.startTime < rhs.startTime
            }
        }
        guard let index = ordered.lastIndex(where: {
            $0.startTime <= playbackTime
        }) else {
            return nil
        }

        let segment = ordered[index]
        let segmentEnd: TimeInterval
        if segment.duration > 0 {
            segmentEnd = segment.startTime + segment.duration
        } else if index + 1 < ordered.count {
            segmentEnd = ordered[index + 1].startTime
        } else {
            segmentEnd = .greatestFiniteMagnitude
        }

        return playbackTime < segmentEnd ? segment.id : nil
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

/// Unlike SwiftUI's indeterminate `ProgressView`, this indicator explicitly
/// restarts whenever a recycled Form row returns to the view hierarchy.
struct PersistentActivityIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> RestartingActivityIndicatorView {
        let indicator = RestartingActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = false
        indicator.startAnimating()
        return indicator
    }

    func updateUIView(
        _ indicator: RestartingActivityIndicatorView,
        context: Context
    ) {
        indicator.ensureAnimating()
    }

    final class RestartingActivityIndicatorView: UIActivityIndicatorView {
        func ensureAnimating() {
            guard !isAnimating else { return }
            startAnimating()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                // UIKit can preserve `isAnimating` after a recycled Form/List
                // row loses its Core Animation. Force a fresh native cycle.
                stopAnimating()
                startAnimating()
            }
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
