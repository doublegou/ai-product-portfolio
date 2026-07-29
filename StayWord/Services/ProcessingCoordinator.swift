import Foundation
import SwiftData

@MainActor
final class ProcessingCoordinator {
    private struct PendingJob {
        let recording: AudioRecording
        let context: ModelContext
    }

    private let fileStore: AudioFileStore
    private let transcriptionService: TranscriptionService
    private let summaryService: any SummaryService
    private var pendingJobs: [UUID: PendingJob] = [:]
    private var pendingJobIDs: [UUID] = []
    private var activeJobID: UUID?
    private var activeTask: Task<Void, Never>?
    private var isApplicationActive = true
    private var didRestoreInterruptedJobs = false

    init(
        fileStore: AudioFileStore,
        transcriptionService: TranscriptionService = TranscriptionService(),
        summaryService: any SummaryService = OnDeviceSummaryService()
    ) {
        self.fileStore = fileStore
        self.transcriptionService = transcriptionService
        self.summaryService = summaryService
    }

    func enqueue(_ recording: AudioRecording, in context: ModelContext) {
        let recordingID = recording.id
        if pendingJobs[recordingID] == nil {
            pendingJobIDs.append(recordingID)
        }
        pendingJobs[recordingID] = PendingJob(
            recording: recording,
            context: context
        )
        startNextJobIfPossible()
    }

    func setApplicationActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else { return }
        isApplicationActive = isActive

        if isActive {
            startNextJobIfPossible()
        } else {
            activeTask?.cancel()
        }
    }

    private func startNextJobIfPossible() {
        guard isApplicationActive,
              activeTask == nil,
              activeJobID == nil,
              let recordingID = pendingJobIDs.first,
              let pendingJob = pendingJobs[recordingID]
        else {
            return
        }

        activeJobID = recordingID
        activeTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.process(
                pendingJob.recording,
                in: pendingJob.context
            )
            self.activeTask = nil
            self.activeJobID = nil

            if !pendingJob.recording.processingState.isOverallProcessing {
                self.pendingJobs[recordingID] = nil
                if self.pendingJobIDs.first == recordingID {
                    self.pendingJobIDs.removeFirst()
                } else {
                    self.pendingJobIDs.removeAll { $0 == recordingID }
                }
            }

            self.startNextJobIfPossible()
        }
    }

    func restoreInterruptedJobs(
        from recordings: [AudioRecording],
        in context: ModelContext
    ) {
        guard !didRestoreInterruptedJobs else { return }
        didRestoreInterruptedJobs = true

        for recording in recordings where recording.processingState.isOverallProcessing {
            enqueue(recording, in: context)
        }
    }

    private func process(_ recording: AudioRecording, in context: ModelContext) async {

        do {
            try Task.checkCancellation()
            recording.failureMessage = nil

            let existingSegments = recording.transcriptSegments
                .sorted { $0.startTime < $1.startTime }
                .map {
                    TranscriptDraft(
                        startTime: $0.startTime,
                        duration: $0.duration,
                        text: $0.text
                    )
                }
            if existingSegments.contains(where: {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }),
               recording.summaryText.isEmpty,
               recording.transcriptionCheckpointSample == 0 {
                try await generateSummary(
                    for: recording,
                    segments: existingSegments,
                    in: context
                )
                return
            }

            recording.processingState = .preparing
            try context.save()

            let audioURL = fileStore.url(for: recording.audioRelativePath)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw StayWordError.recordingNotFound
            }

            let source = try transcriptionSourceIdentity(for: audioURL)
            let canResume =
                recording.transcriptionCheckpointProfileVersion
                    == TranscriptionService.profileVersion
                && recording.transcriptionCheckpointSourceSize == source.size
                && recording.transcriptionCheckpointSourceModifiedAt
                    == source.modifiedAt
                && (
                    recording.transcriptionCheckpointSample == 0
                        || !recording.transcriptSegments.isEmpty
                )

            if !canResume {
                for segment in recording.transcriptSegments {
                    context.delete(segment)
                }
                recording.transcriptSegments.removeAll()
                recording.transcriptionCheckpointSample = 0
                recording.transcriptionCheckpointSourceSize = source.size
                recording.transcriptionCheckpointSourceModifiedAt =
                    source.modifiedAt
                recording.transcriptionCheckpointProfileVersion =
                    TranscriptionService.profileVersion
                try context.save()
            }

            let existingDrafts = recording.transcriptSegments
                .sorted { $0.startTime < $1.startTime }
                .map {
                    TranscriptDraft(
                        startTime: $0.startTime,
                        duration: $0.duration,
                        text: $0.text
                    )
                }
            let drafts = try await transcriptionService.transcribe(
                url: audioURL,
                resumeSampleOffset: recording.transcriptionCheckpointSample,
                existingDrafts: existingDrafts
            ) { stage in
                recording.processingState = stage.processingState
                try? context.save()
            } onEmission: { emission in
                if let draft = emission.draft {
                    let segment = TranscriptSegment(
                        startTime: draft.startTime,
                        duration: draft.duration,
                        text: draft.text,
                        sortOrder: recording.transcriptSegments.count,
                        recording: recording
                    )
                    context.insert(segment)
                    recording.transcriptSegments.append(segment)
                }
                recording.transcriptionCheckpointSample =
                    emission.committedSampleOffset
                try context.save()
            }

            try Task.checkCancellation()

            reconcileTranscript(
                drafts,
                for: recording,
                in: context
            )
            recording.transcriptionCheckpointSample = 0
            recording.transcriptionCheckpointSourceSize = 0
            recording.transcriptionCheckpointSourceModifiedAt = nil
            recording.transcriptionCheckpointProfileVersion = 0
            try context.save()

            try Task.checkCancellation()
            try await generateSummary(
                for: recording,
                segments: drafts,
                in: context
            )
        } catch is CancellationError {
            // Keep the current processing state and any checkpointed work.
            // The pending job restarts when the app becomes active again.
            try? context.save()
        } catch {
            recording.processingState = .failed
            recording.failureMessage = error.localizedDescription
            try? context.save()
        }
    }

    private func transcriptionSourceIdentity(
        for url: URL
    ) throws -> (size: Int64, modifiedAt: Date?) {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date
        return (size, modifiedAt)
    }

    private func reconcileTranscript(
        _ drafts: [TranscriptDraft],
        for recording: AudioRecording,
        in context: ModelContext
    ) {
        let persisted = recording.transcriptSegments
            .sorted { $0.startTime < $1.startTime }

        for (index, draft) in drafts.enumerated() {
            let segment: TranscriptSegment
            if index < persisted.count {
                segment = persisted[index]
            } else {
                segment = TranscriptSegment(
                    startTime: draft.startTime,
                    duration: draft.duration,
                    text: draft.text,
                    sortOrder: index,
                    recording: recording
                )
                context.insert(segment)
                recording.transcriptSegments.append(segment)
            }

            segment.startTime = draft.startTime
            segment.duration = draft.duration
            segment.text = draft.text
            segment.sortOrder = index
        }

        if persisted.count > drafts.count {
            for segment in persisted.dropFirst(drafts.count) {
                recording.transcriptSegments.removeAll { $0.id == segment.id }
                context.delete(segment)
            }
        }
    }

    private func generateSummary(
        for recording: AudioRecording,
        segments: [TranscriptDraft],
        in context: ModelContext
    ) async throws {
        try Task.checkCancellation()
        recording.processingState = .summarizing
        recording.summarySubject = ""
        recording.summaryText = ""
        recording.summaryKind = .none
        recording.summaryFailureMessage = nil
        try context.save()

        let summary: SummaryDraft
        do {
            summary = try await summaryService.summarize(segments: segments)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            recording.processingState = .completed
            recording.summaryFailureMessage = error.localizedDescription
            try context.save()
            return
        }

        try Task.checkCancellation()

        // Preserve edits the user makes while the model is running.
        if recording.summarySubject.isEmpty {
            recording.summarySubject = summary.subject
        }
        if recording.summaryText.isEmpty {
            recording.summaryText = summary.text
            recording.summaryKind = summary.kind
        }

        recording.processingState = .completed
        recording.failureMessage = nil
        recording.summaryFailureMessage = nil
        try context.save()
    }
}
