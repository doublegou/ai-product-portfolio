import AVFAudio
import Foundation
import SwiftData
import Testing
@testable import StayWord

struct StayWordTests {
    @Test
    func timestampFormatting() {
        #expect(TimeInterval(65).audioTimestamp == "01:05")
        #expect(TimeInterval(3_661).audioTimestamp == "1:01:01")
        #expect(TimeInterval(4.8).recordingTimestamp == "00:04.80")
    }

    @Test
    func importedAudioKeepsItsSourceExtension() throws {
        let fileStore = AudioFileStore()
        let importedURL = try fileStore.newImportedAudioURL(
            for: URL(fileURLWithPath: "/tmp/interview.MP3")
        )

        #expect(importedURL.pathExtension == "mp3")
        #expect(try fileStore.newRecordingURL().pathExtension == "m4a")
    }

    @Test
    func recordingDerivedState() {
        let recording = AudioRecording(
            title: "Test",
            duration: 12,
            audioRelativePath: "Recordings/test.m4a",
            waveform: [0.1, 0.5, 0.9]
        )
        recording.processingState = .summarizing
        recording.summaryKind = .extractive
        recording.summaryFailureMessage = "Summary unavailable"

        #expect(recording.processingState == .summarizing)
        #expect(recording.summaryKind == .extractive)
        #expect(recording.summaryFailureMessage == "Summary unavailable")
        #expect(recording.waveform == [0.1, 0.5, 0.9])
    }

    @Test
    func processingStagesHaveIndependentDisplayLifecycles() {
        let transcriptionStages: [ProcessingState] = [
            .ready,
            .preparing,
            .vad,
            .transcribing,
        ]

        for state in transcriptionStages {
            #expect(state.isTranscriptionProcessing)
            #expect(state.isOverallProcessing)
        }

        #expect(!ProcessingState.summarizing.isTranscriptionProcessing)
        #expect(ProcessingState.summarizing.isOverallProcessing)

        for state in [ProcessingState.completed, .failed] {
            #expect(!state.isTranscriptionProcessing)
            #expect(!state.isOverallProcessing)
        }
    }

    @Test
    @MainActor
    func processingPausesInBackgroundAndResumesWhenActive() async throws {
        let schema = Schema([
            RecordingFolder.self,
            AudioRecording.self,
            TranscriptSegment.self,
            RecordingMarker.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        let summaryService = LifecycleSummaryService()
        let coordinator = ProcessingCoordinator(
            fileStore: AudioFileStore(),
            summaryService: summaryService
        )
        let recording = AudioRecording(
            title: "Background Test",
            duration: 10,
            audioRelativePath: "Recordings/background-test.m4a",
            processingState: .summarizing
        )
        let segment = TranscriptSegment(
            startTime: 0,
            duration: 2,
            text: "A transcript that can be summarized.",
            recording: recording
        )
        context.insert(recording)
        context.insert(segment)
        recording.transcriptSegments.append(segment)
        try context.save()

        coordinator.enqueue(recording, in: context)
        for _ in 0..<100 {
            if await summaryService.attemptCount() == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await summaryService.attemptCount() == 1)

        coordinator.setApplicationActive(false)
        for _ in 0..<100 {
            if await summaryService.cancellationCount() == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await summaryService.cancellationCount() == 1)
        #expect(recording.processingState == .summarizing)

        coordinator.setApplicationActive(true)
        for _ in 0..<100 {
            if recording.processingState == .completed { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await summaryService.attemptCount() == 2)
        #expect(recording.processingState == .completed)
        #expect(recording.summaryText == "Resumed summary")
    }

    @Test
    @MainActor
    func recordingsProcessOneAtATimeInFIFOOrder() async throws {
        let schema = Schema([
            RecordingFolder.self,
            AudioRecording.self,
            TranscriptSegment.self,
            RecordingMarker.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        let summaryService = QueueProbeSummaryService()
        let coordinator = ProcessingCoordinator(
            fileStore: AudioFileStore(),
            summaryService: summaryService
        )
        let recordings = ["First", "Second", "Third"].map { label in
            let recording = AudioRecording(
                title: label,
                duration: 10,
                audioRelativePath: "Recordings/\(label).m4a"
            )
            let segment = TranscriptSegment(
                startTime: 0,
                duration: 2,
                text: label,
                recording: recording
            )
            context.insert(recording)
            context.insert(segment)
            recording.transcriptSegments.append(segment)
            return recording
        }
        try context.save()

        for recording in recordings {
            coordinator.enqueue(recording, in: context)
        }

        for _ in 0..<100 {
            if await summaryService.startedLabels().count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await summaryService.startedLabels() == ["First"])
        #expect(await summaryService.maximumConcurrentCount() == 1)
        #expect(recordings[0].processingState == .summarizing)
        #expect(recordings[1].processingState == .ready)
        #expect(recordings[2].processingState == .ready)

        await summaryService.releaseNext()
        for _ in 0..<100 {
            if await summaryService.startedLabels().count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await summaryService.startedLabels() == ["First", "Second"])
        #expect(await summaryService.maximumConcurrentCount() == 1)
        #expect(recordings[0].processingState == .completed)
        #expect(recordings[1].processingState == .summarizing)
        #expect(recordings[2].processingState == .ready)

        await summaryService.releaseNext()
        for _ in 0..<100 {
            if await summaryService.startedLabels().count == 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await summaryService.startedLabels() == ["First", "Second", "Third"])
        #expect(await summaryService.maximumConcurrentCount() == 1)

        await summaryService.releaseNext()
        for _ in 0..<100 {
            if recordings.allSatisfy({ $0.processingState == .completed }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recordings.allSatisfy { $0.processingState == .completed })
        #expect(recordings.map(\.summaryText) == ["First", "Second", "Third"])
    }

    @Test
    @MainActor
    func swiftDataFolderRelationship() throws {
        let schema = Schema([
            RecordingFolder.self,
            AudioRecording.self,
            TranscriptSegment.self,
            RecordingMarker.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let folder = RecordingFolder(name: "Meetings")
        let recording = AudioRecording(
            title: "Interview",
            duration: 30,
            audioRelativePath: "Recordings/interview.m4a",
            folder: folder
        )
        context.insert(folder)
        context.insert(recording)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AudioRecording>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.folder?.name == "Meetings")
    }

    @Test
    func transcriptDraftRetainsSegmentTiming() {
        let drafts = [
            TranscriptDraft(
                startTime: 10,
                duration: 4,
                text: "Hello"
            ),
            TranscriptDraft(
                startTime: 14,
                duration: 3,
                text: "World"
            ),
        ]

        #expect(drafts.map(\.startTime) == [10, 14])
        #expect(drafts.map(\.duration) == [4, 3])
        #expect(drafts.map(\.text) == ["Hello", "World"])
    }

    @Test
    func summaryChunksKeepTranscriptSegmentsWholeAndOrdered() {
        let segments = [
            TranscriptDraft(startTime: 0, duration: 1, text: "First"),
            TranscriptDraft(startTime: 1, duration: 1, text: "Second"),
            TranscriptDraft(startTime: 2, duration: 1, text: "Third"),
        ]

        let chunks = SummaryInputChunker.chunks(
            from: segments,
            targetCharacterCount: 12
        )

        #expect(chunks == ["First\nSecond", "Third"])
    }

    @Test
    func summaryChunksMayPassTheTargetToKeepTheNextSegmentWhole() {
        let segments = [
            TranscriptDraft(startTime: 0, duration: 1, text: "123456789"),
            TranscriptDraft(startTime: 1, duration: 1, text: "AB"),
            TranscriptDraft(startTime: 2, duration: 1, text: "Tail"),
        ]

        let chunks = SummaryInputChunker.chunks(
            from: segments,
            targetCharacterCount: 10
        )

        #expect(chunks == ["123456789\nAB", "Tail"])
    }

    @Test
    func summaryChunksDoNotSplitAnOversizedTranscriptSegment() {
        let oversizedText = String(repeating: "x", count: 20)
        let segments = [
            TranscriptDraft(startTime: 0, duration: 1, text: oversizedText),
            TranscriptDraft(startTime: 1, duration: 1, text: "Tail"),
        ]

        let chunks = SummaryInputChunker.chunks(
            from: segments,
            targetCharacterCount: 10
        )

        #expect(chunks == [oversizedText, "Tail"])
    }

    @Test
    func structuredSummaryOutputParsesTitleAndReadableBody() throws {
        let output = try #require(SummaryOutputParser.parse(
            """
            <think>Internal reasoning</think>
            ```xml
            <title>项目方向与后续安排</title>
            <summary>
            团队确认了新的项目方向。

            - 下周完成第一版方案
            - 测试完成后复盘
            </summary>
            ```
            """
        ))

        #expect(output.title == "项目方向与后续安排")
        #expect(output.summary == """
            团队确认了新的项目方向。

            - 下周完成第一版方案
            - 测试完成后复盘
            """)
    }

    @Test
    func structuredSummaryOutputRemovesParagraphMarkup() throws {
        let output = try #require(SummaryOutputParser.parse(
            """
            <title><p>强化学习云方案分歧</p></title>
            <summary><p>第一段核心内容。</p><p>第二段核心内容。</p></summary>
            """
        ))

        #expect(output.title == "强化学习云方案分歧")
        #expect(output.summary == "第一段核心内容。\n\n第二段核心内容。")
    }

    @Test
    func summaryMarkupCleanerConvertsHTMLListsToPlainText() {
        #expect(SummaryMarkupCleaner.clean(
            "<ul><li><strong>事项一</strong></li><li>事项二<br>补充</li></ul>"
        ) == "- 事项一\n- 事项二\n补充")
    }

    @Test
    func structuredSummaryOutputRequiresBothFields() {
        #expect(SummaryOutputParser.parse(
            "<summary>只有正文，没有标题。</summary>"
        ) == nil)
    }

    @Test
    func bestEffortSummaryAcceptsAnUnclosedSummaryTag() throws {
        let output = try #require(SummaryOutputParser.parseBestEffort(
            """
            <title>项目进展</title>
            <summary>
            第一阶段已经完成，下一步进入验证。
            """
        ))

        #expect(output.title == "项目进展")
        #expect(output.summary == "第一阶段已经完成，下一步进入验证。")
    }

    @Test
    func bestEffortSummaryAcceptsLabeledPlainText() throws {
        let output = try #require(SummaryOutputParser.parseBestEffort(
            """
            标题：产品讨论
            摘要：团队确认先验证核心流程，再扩展次要功能。
            """
        ))

        #expect(output.title == "产品讨论")
        #expect(output.summary == "团队确认先验证核心流程，再扩展次要功能。")
    }

    @Test
    func bestEffortSummaryPreservesUntaggedBody() throws {
        let output = try #require(SummaryOutputParser.parseBestEffort(
            "团队决定先完成原型验证。验证通过后再进入正式开发。"
        ))

        #expect(output.title == "团队决定先完成原型验证")
        #expect(output.summary == "团队决定先完成原型验证。验证通过后再进入正式开发。")
    }

    @Test
    func partialSummaryOutputParsesTaggedBody() {
        #expect(PartialSummaryOutputParser.parse(
            """
            <think>不应保留的思考过程</think>
            <partial_summary>
            保留下来的分段摘要。
            </partial_summary>
            """
        ) == "保留下来的分段摘要。")
    }

    @Test
    func partialSummaryOutputKeepsUsableBodyWhenClosingTagIsMissing() {
        #expect(PartialSummaryOutputParser.parse(
            "<partial_summary>达到安全上限前已经生成的有效摘要。"
        ) == "达到安全上限前已经生成的有效摘要。")
    }

    @Test
    func summaryResponseStopsAtClosingSummaryTag() throws {
        let completed = try #require(SummaryResponseStopper.completedPrefix(
            in: "<title>标题</title><summary>正文</summary>不应保留",
            closingTag: "</summary>"
        ))

        #expect(completed == "<title>标题</title><summary>正文</summary>")
    }

    @Test
    func summaryResponseWaitsForACompleteClosingTag() {
        #expect(SummaryResponseStopper.completedPrefix(
            in: "<title>标题</title><summary>正文</sum",
            closingTag: "</summary>"
        ) == nil)
    }

    @Test
    @MainActor
    func transcriptionCheckpointPersistsWithRecording() throws {
        let schema = Schema([
            RecordingFolder.self,
            AudioRecording.self,
            TranscriptSegment.self,
            RecordingMarker.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let recording = AudioRecording(
            title: "Checkpoint",
            duration: 300,
            audioRelativePath: "Recordings/checkpoint.m4a",
            transcriptionCheckpointSample: 96_000,
            transcriptionCheckpointSourceSize: 42,
            transcriptionCheckpointSourceModifiedAt: modifiedAt,
            transcriptionCheckpointProfileVersion: TranscriptionService.profileVersion
        )
        context.insert(recording)
        try context.save()

        let fetched = try #require(
            context.fetch(FetchDescriptor<AudioRecording>()).first
        )
        #expect(fetched.transcriptionCheckpointSample == 96_000)
        #expect(fetched.transcriptionCheckpointSourceSize == 42)
        #expect(fetched.transcriptionCheckpointSourceModifiedAt == modifiedAt)
        #expect(
            fetched.transcriptionCheckpointProfileVersion
                == TranscriptionService.profileVersion
        )
    }

    @Test
    func transcriptPlaybackSyncUsesSpokenSegmentBounds() {
        let first = TranscriptSegment(
            startTime: 1,
            duration: 2,
            text: "First"
        )
        let second = TranscriptSegment(
            startTime: 4,
            duration: 2,
            text: "Second"
        )
        let segments = [second, first]

        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 0.9) == nil)
        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 1) == first.id)
        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 2.9) == first.id)
        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 3) == nil)
        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 4) == second.id)
        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 6) == nil)
    }

    @Test
    func transcriptPlaybackSyncSupportsLegacyUntimedSegments() {
        let first = TranscriptSegment(
            startTime: 0,
            text: "First",
            sortOrder: 0
        )
        let second = TranscriptSegment(
            startTime: 5,
            text: "Second",
            sortOrder: 1
        )
        let segments = [second, first]

        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 4.9) == first.id)
        #expect(TranscriptPlaybackSync.activeSegmentID(in: segments, at: 5) == second.id)
    }

    @Test
    func aacPreparationStopsCleanlyAtEndOfFile() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
        }

        let sourceFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ))
        var sourceFile: AVAudioFile? = try AVAudioFile(
            forWriting: sourceURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frameCount: AVAudioFrameCount = 22_050
        let sourceBuffer = try #require(AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: frameCount
        ))
        sourceBuffer.frameLength = frameCount
        let channel = try #require(sourceBuffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            channel[frame] = sin(Float(frame) * 0.04) * 0.2
        }
        try sourceFile?.write(from: sourceBuffer)
        sourceFile = nil

        let prepared = try await AudioPCMPreparer().prepare(contentsOf: sourceURL)
        defer {
            try? prepared.remove()
        }

        #expect(prepared.metadata.sampleRate == 16_000)
        #expect(prepared.metadata.channelCount == 1)
        #expect(prepared.metadata.frameCount > 0)
        #expect(abs(prepared.metadata.duration - 0.5) < 0.03)
    }
}

private actor LifecycleSummaryService: SummaryService {
    private var attempts = 0
    private var cancellations = 0

    func summarize(segments: [TranscriptDraft]) async throws -> SummaryDraft {
        attempts += 1

        if attempts == 1 {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch is CancellationError {
                cancellations += 1
                throw CancellationError()
            }
        }

        return SummaryDraft(
            subject: "",
            text: "Resumed summary",
            kind: .extractive
        )
    }

    func attemptCount() -> Int {
        attempts
    }

    func cancellationCount() -> Int {
        cancellations
    }
}

private actor QueueProbeSummaryService: SummaryService {
    private var labels: [String] = []
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func summarize(segments: [TranscriptDraft]) async throws -> SummaryDraft {
        let label = segments.first?.text ?? ""
        labels.append(label)
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }

        activeCount -= 1
        return SummaryDraft(
            subject: label,
            text: label,
            kind: .extractive
        )
    }

    func startedLabels() -> [String] {
        labels
    }

    func maximumConcurrentCount() -> Int {
        maximumActiveCount
    }

    func releaseNext() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}
