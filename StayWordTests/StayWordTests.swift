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
    func transcriptCannotBePersistedAsItsOwnSummary() {
        #expect(!SummaryContentPolicy.isDistinctSummary(
            "今天 下午 三点开会。",
            from: "今天下午三点开会"
        ))
        #expect(SummaryContentPolicy.isDistinctSummary(
            "会议安排在今天下午三点。",
            from: "大家讨论了项目进度，最后决定今天下午三点开会。"
        ))
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
    func speakerTurnsAreAlignedAndNormalizedByFirstAppearance() {
        let units = TranscriptionSegmentPlanner.makeUnits(
            speech: [
                SherpaSpeechInterval(start: 0, end: 8),
            ],
            speakerTurns: [
                SherpaSpeakerTurn(start: 0, end: 3, speaker: 7),
                SherpaSpeakerTurn(start: 3, end: 8, speaker: 2),
            ],
            audioDuration: 8
        )

        #expect(units == [
            TranscriptionUnit(start: 0, end: 3, speaker: 0),
            TranscriptionUnit(start: 3, end: 8, speaker: 1),
        ])
    }

    @Test
    func speechWithoutDiarizationRemainsTranscribable() {
        let units = TranscriptionSegmentPlanner.makeUnits(
            speech: [
                SherpaSpeechInterval(start: 1, end: 2.5),
            ],
            speakerTurns: [],
            audioDuration: 4
        )

        #expect(units == [
            TranscriptionUnit(start: 1, end: 2.5, speaker: nil),
        ])
    }

    @Test
    func provisionalTranscriptsReceiveDominantSpeakerAfterDiarization() {
        let drafts = [
            TranscriptDraft(
                startTime: 10,
                duration: 4,
                text: "Hello",
                speakerIndex: nil
            ),
            TranscriptDraft(
                startTime: 14,
                duration: 3,
                text: "World",
                speakerIndex: nil
            ),
        ]

        let assigned = TranscriptionService.assignSpeakers(
            to: drafts,
            from: [
                SherpaSpeakerTurn(start: 10, end: 11, speaker: 0),
                SherpaSpeakerTurn(start: 11, end: 14, speaker: 1),
                SherpaSpeakerTurn(start: 14, end: 17, speaker: 0),
            ]
        )

        #expect(assigned.map(\.speakerIndex) == [1, 0])
        #expect(assigned.map(\.text) == ["Hello", "World"])
    }

    @Test
    func speakerWindowOverlapKeepsSingleSpeakerStable() {
        let mapper = SpeakerWindowMapper()
        mapper.consume(
            [SherpaSpeakerTurn(start: 0, end: 90, speaker: 4)],
            commitRange: 0..<80
        )
        mapper.consume(
            [SherpaSpeakerTurn(start: 80, end: 170, speaker: 9)],
            commitRange: 80..<170
        )

        #expect(mapper.finish() == [
            SherpaSpeakerTurn(start: 0, end: 170, speaker: 0),
        ])
    }

    @Test
    func speakerWindowOverlapMapsRemainingKnownSpeaker() {
        let mapper = SpeakerWindowMapper()
        mapper.consume(
            [
                SherpaSpeakerTurn(start: 0, end: 45, speaker: 3),
                SherpaSpeakerTurn(start: 45, end: 90, speaker: 8),
            ],
            commitRange: 0..<80
        )
        mapper.consume(
            [
                SherpaSpeakerTurn(start: 80, end: 100, speaker: 2),
                SherpaSpeakerTurn(start: 100, end: 170, speaker: 7),
            ],
            commitRange: 80..<170
        )

        #expect(Set(mapper.finish().map(\.speaker)) == [0, 1])
    }

    @Test
    func speakerEmbeddingReconnectsSpeakerAfterLongSilence() {
        let mapper = SpeakerWindowMapper()
        mapper.consume(
            [
                SherpaSpeakerTurn(start: 0, end: 40, speaker: 3),
                SherpaSpeakerTurn(start: 40, end: 90, speaker: 8),
            ],
            commitRange: 0..<80,
            embeddings: [
                3: [1, 0],
                8: [0, 1],
            ]
        )
        mapper.consume(
            [SherpaSpeakerTurn(start: 200, end: 250, speaker: 5)],
            commitRange: 200..<250,
            embeddings: [
                5: [0.99, 0.01],
            ]
        )

        #expect(mapper.finish().last?.speaker == 0)
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
