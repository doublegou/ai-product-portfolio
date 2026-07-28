import Foundation
import SwiftData

@MainActor
final class ProcessingCoordinator {
    private let fileStore: AudioFileStore
    private let transcriptionService: TranscriptionService
    private let summaryService: any SummaryService
    private var jobs: [UUID: Task<Void, Never>] = [:]
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
        guard jobs[recordingID] == nil else { return }

        jobs[recordingID] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.process(recording, in: context)
            self.jobs[recordingID] = nil
        }
    }

    func restoreInterruptedJobs(
        from recordings: [AudioRecording],
        in context: ModelContext
    ) {
        guard !didRestoreInterruptedJobs else { return }
        didRestoreInterruptedJobs = true

        for recording in recordings where recording.processingState.isProcessing {
            enqueue(recording, in: context)
        }
    }

    private func process(_ recording: AudioRecording, in context: ModelContext) async {

        do {
            recording.failureMessage = nil

            let existingTranscript = recording.transcriptText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !existingTranscript.isEmpty, recording.summaryText.isEmpty {
                try await generateSummary(
                    for: recording,
                    transcript: existingTranscript,
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

            let drafts = try await transcriptionService.transcribe(
                url: audioURL
            ) { stage in
                recording.processingState = stage.processingState
                try? context.save()
            }

            recording.transcriptSegments.removeAll()
            for (index, draft) in drafts.enumerated() {
                let segment = TranscriptSegment(
                    startTime: draft.startTime,
                    duration: draft.duration,
                    text: draft.text,
                    sortOrder: index,
                    speakerIndex: draft.speakerIndex,
                    recording: recording
                )
                context.insert(segment)
                recording.transcriptSegments.append(segment)
            }

            try await generateSummary(
                for: recording,
                transcript: drafts.map(\.text).joined(separator: "\n"),
                in: context
            )
        } catch {
            recording.processingState = .failed
            recording.failureMessage = error.localizedDescription
            try? context.save()
        }
    }

    private func generateSummary(
        for recording: AudioRecording,
        transcript: String,
        in context: ModelContext
    ) async throws {
        recording.processingState = .summarizing
        recording.summarySubject = ""
        recording.summaryText = ""
        recording.summaryKind = .none
        try context.save()

        let summary = try await summaryService.summarize(
            transcript: transcript
        )

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
        try context.save()
    }
}
