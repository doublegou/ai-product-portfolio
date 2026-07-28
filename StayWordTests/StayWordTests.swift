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

        #expect(recording.processingState == .summarizing)
        #expect(recording.summaryKind == .extractive)
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
