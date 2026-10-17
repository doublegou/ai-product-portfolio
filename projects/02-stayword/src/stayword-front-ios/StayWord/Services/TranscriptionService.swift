import AVFAudio
import Foundation

struct TranscriptDraft: Sendable, Equatable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let text: String
}

struct TranscriptEmission: Sendable, Equatable {
    let draft: TranscriptDraft?
    let committedSampleOffset: Int64
}

enum TranscriptionStage: Sendable {
    case preparing
    case detectingSpeech
    case transcribing

    var processingState: ProcessingState {
        switch self {
        case .preparing:
            .preparing
        case .detectingSpeech:
            .vad
        case .transcribing:
            .transcribing
        }
    }
}

/// The app's single production transcription engine.
///
/// Audio is normalized once and read in bounded chunks. Streaming VAD produces
/// timestamped utterances, and each completed utterance is transcribed
/// immediately. No audio leaves the device and no full-recording post-pass is
/// required.
actor TranscriptionService {
    static let profileVersion = 3

    private static let sampleRate: Int32 = 16_000
    private static let readBatchFrames: AVAudioFrameCount = 80_000

    private let pcmPreparer: AudioPCMPreparer
    private let injectedRuntime: SherpaOnnxRuntime?

    init(
        pcmPreparer: AudioPCMPreparer = AudioPCMPreparer(),
        runtime: SherpaOnnxRuntime? = nil
    ) {
        self.pcmPreparer = pcmPreparer
        self.injectedRuntime = runtime
    }

    func transcribe(
        url: URL,
        language: TranscriptionLanguage = .mandarinChinese
    ) async throws -> [TranscriptDraft] {
        try await transcribe(
            url: url,
            language: language,
            resumeSampleOffset: 0,
            existingDrafts: [],
            onStage: { _ in },
            onEmission: { _ in }
        )
    }

    func transcribe(
        url: URL,
        language: TranscriptionLanguage = .mandarinChinese,
        resumeSampleOffset: Int64 = 0,
        existingDrafts: [TranscriptDraft] = [],
        onStage: @escaping @MainActor @Sendable (TranscriptionStage) -> Void,
        onEmission: @escaping @MainActor @Sendable (TranscriptEmission) throws -> Void
    ) async throws -> [TranscriptDraft] {
        try Task.checkCancellation()
        await onStage(.preparing)

        let prepared = try await pcmPreparer.prepare(contentsOf: url)
        defer {
            if prepared.isTemporary {
                try? prepared.remove()
            }
        }

        let runtime = try injectedRuntime ?? SherpaOnnxRuntime()
        let boundedResumeOffset = min(
            max(0, resumeSampleOffset),
            prepared.metadata.frameCount
        )
        var drafts = existingDrafts.sorted { $0.startTime < $1.startTime }

        if boundedResumeOffset < prepared.metadata.frameCount {
            try Task.checkCancellation()
            await onStage(.detectingSpeech)
            let session = try runtime.makeStreamingRecognizer(
                sampleRate: Self.sampleRate,
                baseSampleOffset: boundedResumeOffset,
                language: language
            )
            let reader = try PreparedPCMReader(
                prepared: prepared,
                startFrame: boundedResumeOffset,
                frameCapacity: Self.readBatchFrames
            )

            await onStage(.transcribing)
            while let samples = try reader.readNext() {
                try Task.checkCancellation()
                let results = try session.accept(samples)
                for result in results {
                    let emission = Self.emission(from: result)
                    if let draft = emission.draft {
                        drafts.append(draft)
                    }
                    try await onEmission(emission)
                }
                await Task.yield()
            }

            for result in try session.finish() {
                let emission = Self.emission(from: result)
                if let draft = emission.draft {
                    drafts.append(draft)
                }
                try await onEmission(emission)
            }
        }

        guard !drafts.isEmpty else {
            throw StayWordError.emptyTranscript
        }
        return drafts
    }

    private static func emission(
        from result: SherpaStreamingTranscript
    ) -> TranscriptEmission {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = text.isEmpty
            ? nil
            : TranscriptDraft(
                startTime: TimeInterval(result.startSample)
                    / TimeInterval(Self.sampleRate),
                duration: TimeInterval(result.endSample - result.startSample)
                    / TimeInterval(Self.sampleRate),
                text: text
            )
        return TranscriptEmission(
            draft: draft,
            committedSampleOffset: result.endSample
        )
    }
}

private final class PreparedPCMReader {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer

    init(
        prepared: PreparedPCMFile,
        startFrame: Int64,
        frameCapacity: AVAudioFrameCount
    ) throws {
        file = try AVAudioFile(forReading: prepared.url)
        let format = file.processingFormat
        guard
            format.sampleRate == AudioPCMPreparer.outputSampleRate,
            format.channelCount == AudioPCMPreparer.outputChannelCount,
            format.commonFormat == .pcmFormatFloat32,
            startFrame >= 0,
            startFrame <= file.length,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCapacity
            )
        else {
            throw StayWordError.invalidAudioFile
        }
        self.buffer = buffer
        file.framePosition = startFrame
    }

    func readNext() throws -> [Float]? {
        guard file.framePosition < file.length else { return nil }
        buffer.frameLength = 0
        let remaining = file.length - file.framePosition
        let count = min(buffer.frameCapacity, AVAudioFrameCount(remaining))
        try file.read(into: buffer, frameCount: count)
        guard
            buffer.frameLength > 0,
            let channel = buffer.floatChannelData?[0]
        else {
            return nil
        }
        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            )
        )
    }
}
