import AVFAudio
import Foundation

struct TranscriptDraft: Sendable, Equatable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let text: String
    let speakerIndex: Int?
}

enum TranscriptionStage: Sendable {
    case preparing
    case detectingSpeech
    case identifyingSpeakers
    case aligning
    case transcribing

    var processingState: ProcessingState {
        switch self {
        case .preparing:
            .preparing
        case .detectingSpeech:
            .vad
        case .identifyingSpeakers:
            .diarizing
        case .aligning:
            .aligning
        case .transcribing:
            .transcribing
        }
    }
}

/// The app's single production transcription engine.
///
/// Audio is normalized once, speech and speaker turns are detected locally,
/// and SenseVoice transcribes speaker-aligned utterances. No audio leaves the
/// device and there is no second engine-selection path.
actor TranscriptionService {
    private static let sampleRate: Int32 = 16_000

    private let pcmPreparer: AudioPCMPreparer
    private let injectedRuntime: SherpaOnnxRuntime?

    init(
        pcmPreparer: AudioPCMPreparer = AudioPCMPreparer(),
        runtime: SherpaOnnxRuntime? = nil
    ) {
        self.pcmPreparer = pcmPreparer
        self.injectedRuntime = runtime
    }

    func transcribe(url: URL) async throws -> [TranscriptDraft] {
        try await transcribe(url: url) { _ in }
    }

    func transcribe(
        url: URL,
        onStage: @escaping @MainActor @Sendable (TranscriptionStage) -> Void
    ) async throws -> [TranscriptDraft] {
        try Task.checkCancellation()
        await onStage(.preparing)

        let prepared = try await pcmPreparer.prepare(contentsOf: url)
        defer {
            if prepared.isTemporary {
                try? prepared.remove()
            }
        }

        let samples = try loadSamples(from: prepared)
        let runtime = try injectedRuntime ?? SherpaOnnxRuntime()
        try Task.checkCancellation()

        await onStage(.detectingSpeech)
        let speech = try runtime.detectSpeech(
            samples: samples,
            sampleRate: Self.sampleRate
        )
        guard !speech.isEmpty else {
            throw StayWordError.emptyTranscript
        }

        try Task.checkCancellation()
        await onStage(.identifyingSpeakers)
        let speakerTurns = try runtime.diarize(
            samples: samples,
            sampleRate: Self.sampleRate
        )

        try Task.checkCancellation()
        await onStage(.aligning)
        let units = TranscriptionSegmentPlanner.makeUnits(
            speech: speech,
            speakerTurns: speakerTurns,
            audioDuration: prepared.metadata.duration
        )
        guard !units.isEmpty else {
            throw StayWordError.emptyTranscript
        }

        let sampleRanges = units.compactMap {
            $0.sampleRange(
                sampleRate: Int(Self.sampleRate),
                sampleCount: samples.count
            )
        }
        guard sampleRanges.count == units.count else {
            throw StayWordError.invalidAudioFile
        }

        try Task.checkCancellation()
        await onStage(.transcribing)
        let texts = try runtime.transcribe(
            ranges: sampleRanges,
            in: samples,
            sampleRate: Self.sampleRate
        )
        guard texts.count == units.count else {
            throw StayWordError.emptyTranscript
        }

        let drafts = zip(units, texts).compactMap { unit, rawText -> TranscriptDraft? in
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return TranscriptDraft(
                startTime: unit.start,
                duration: unit.end - unit.start,
                text: text,
                speakerIndex: unit.speaker
            )
        }

        guard !drafts.isEmpty else {
            throw StayWordError.emptyTranscript
        }
        return drafts
    }

    private func loadSamples(from prepared: PreparedPCMFile) throws -> [Float] {
        let file = try AVAudioFile(forReading: prepared.url)
        let format = file.processingFormat

        guard
            format.sampleRate == Double(Self.sampleRate),
            format.channelCount == 1,
            format.commonFormat == .pcmFormatFloat32,
            prepared.metadata.frameCount <= Int64(Int.max)
        else {
            throw StayWordError.invalidAudioFile
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int(prepared.metadata.frameCount))

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 16_384
        ) else {
            throw StayWordError.invalidAudioFile
        }

        while file.framePosition < file.length {
            try Task.checkCancellation()
            buffer.frameLength = 0
            let remainingFrames = file.length - file.framePosition
            let frameCount = min(
                buffer.frameCapacity,
                AVAudioFrameCount(remainingFrames)
            )
            try file.read(into: buffer, frameCount: frameCount)
            guard buffer.frameLength > 0 else { break }
            guard let channel = buffer.floatChannelData?[0] else {
                throw StayWordError.invalidAudioFile
            }
            samples.append(contentsOf: UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            ))
        }

        guard !samples.isEmpty else {
            throw StayWordError.emptyTranscript
        }
        return samples
    }
}

struct TranscriptionUnit: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let speaker: Int?

    func sampleRange(sampleRate: Int, sampleCount: Int) -> Range<Int>? {
        let lower = max(0, min(sampleCount, Int((start * Double(sampleRate)).rounded(.down))))
        let upper = max(0, min(sampleCount, Int((end * Double(sampleRate)).rounded(.up))))
        guard lower < upper else { return nil }
        return lower..<upper
    }
}

enum TranscriptionSegmentPlanner {
    private static let minimumUnitDuration: TimeInterval = 0.18
    private static let mergeGap: TimeInterval = 0.20
    private static let maximumUnitDuration: TimeInterval = 28

    static func makeUnits(
        speech: [SherpaSpeechInterval],
        speakerTurns: [SherpaSpeakerTurn],
        audioDuration: TimeInterval
    ) -> [TranscriptionUnit] {
        let duration = max(0, audioDuration)
        var atoms: [TranscriptionUnit] = []

        for interval in speech.sorted(by: { $0.start < $1.start }) {
            let speechStart = min(max(0, interval.start), duration)
            let speechEnd = min(max(speechStart, interval.end), duration)
            guard speechEnd - speechStart >= minimumUnitDuration else { continue }

            let overlaps = speakerTurns.filter {
                $0.end > speechStart && $0.start < speechEnd
            }
            var boundaries = [speechStart, speechEnd]
            for turn in overlaps {
                boundaries.append(min(max(turn.start, speechStart), speechEnd))
                boundaries.append(min(max(turn.end, speechStart), speechEnd))
            }
            boundaries = Array(Set(boundaries)).sorted()

            for (start, end) in zip(boundaries, boundaries.dropFirst()) {
                guard end - start >= minimumUnitDuration else { continue }
                let speaker = dominantSpeaker(
                    between: start,
                    and: end,
                    turns: overlaps
                )
                atoms.append(
                    TranscriptionUnit(start: start, end: end, speaker: speaker)
                )
            }
        }

        let merged = mergeAdjacent(atoms)
        let split = merged.flatMap(splitLongUnit)
        return normalizeSpeakerIndices(split)
    }

    private static func dominantSpeaker(
        between start: TimeInterval,
        and end: TimeInterval,
        turns: [SherpaSpeakerTurn]
    ) -> Int? {
        turns
            .map { turn in
                let overlap = max(0, min(end, turn.end) - max(start, turn.start))
                return (speaker: turn.speaker, overlap: overlap)
            }
            .filter { $0.overlap > 0 }
            .max {
                if $0.overlap == $1.overlap {
                    return $0.speaker > $1.speaker
                }
                return $0.overlap < $1.overlap
            }?
            .speaker
    }

    private static func mergeAdjacent(
        _ units: [TranscriptionUnit]
    ) -> [TranscriptionUnit] {
        var result: [TranscriptionUnit] = []

        for unit in units.sorted(by: { $0.start < $1.start }) {
            guard let previous = result.last else {
                result.append(unit)
                continue
            }

            let gap = unit.start - previous.end
            let combinedDuration = unit.end - previous.start
            if previous.speaker == unit.speaker,
               gap <= mergeGap,
               combinedDuration <= maximumUnitDuration {
                result[result.count - 1] = TranscriptionUnit(
                    start: previous.start,
                    end: max(previous.end, unit.end),
                    speaker: previous.speaker
                )
            } else {
                result.append(unit)
            }
        }
        return result
    }

    private static func splitLongUnit(
        _ unit: TranscriptionUnit
    ) -> [TranscriptionUnit] {
        guard unit.end - unit.start > maximumUnitDuration else {
            return [unit]
        }

        var result: [TranscriptionUnit] = []
        var start = unit.start
        while start < unit.end {
            let end = min(start + maximumUnitDuration, unit.end)
            if end - start >= minimumUnitDuration {
                result.append(
                    TranscriptionUnit(
                        start: start,
                        end: end,
                        speaker: unit.speaker
                    )
                )
            }
            start = end
        }
        return result
    }

    private static func normalizeSpeakerIndices(
        _ units: [TranscriptionUnit]
    ) -> [TranscriptionUnit] {
        var normalized: [Int: Int] = [:]
        var nextIndex = 0

        return units.map { unit in
            guard let original = unit.speaker else { return unit }
            let speaker = normalized[original] ?? {
                defer { nextIndex += 1 }
                normalized[original] = nextIndex
                return nextIndex
            }()
            return TranscriptionUnit(
                start: unit.start,
                end: unit.end,
                speaker: speaker
            )
        }
    }
}
