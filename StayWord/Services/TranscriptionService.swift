import AVFAudio
import Foundation

struct TranscriptDraft: Sendable, Equatable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let text: String
    let speakerIndex: Int?
}

struct TranscriptEmission: Sendable, Equatable {
    let draft: TranscriptDraft?
    let committedSampleOffset: Int64
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
/// Audio is normalized once and read in bounded chunks. Completed VAD
/// utterances are transcribed immediately, then overlapping diarization windows
/// assign speaker labels without retaining the complete recording in memory.
/// No audio leaves the device and there is no second engine-selection path.
actor TranscriptionService {
    static let profileVersion = 2

    private static let sampleRate: Int32 = 16_000
    private static let readBatchFrames: AVAudioFrameCount = 80_000
    private static let diarizationWindowFrames: AVAudioFramePosition = 1_440_000
    private static let diarizationOverlapFrames: AVAudioFramePosition = 160_000

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
        try await transcribe(
            url: url,
            resumeSampleOffset: 0,
            existingDrafts: [],
            onStage: { _ in },
            onEmission: { _ in }
        )
    }

    func transcribe(
        url: URL,
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
                baseSampleOffset: boundedResumeOffset
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

        try Task.checkCancellation()
        await onStage(.identifyingSpeakers)
        let speakerTurns = try await windowedDiarization(
            prepared: prepared,
            runtime: runtime
        )

        try Task.checkCancellation()
        await onStage(.aligning)
        return Self.assignSpeakers(to: drafts, from: speakerTurns)
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
                text: text,
                speakerIndex: nil
            )
        return TranscriptEmission(
            draft: draft,
            committedSampleOffset: result.endSample
        )
    }

    private func windowedDiarization(
        prepared: PreparedPCMFile,
        runtime: SherpaOnnxRuntime
    ) async throws -> [SherpaSpeakerTurn] {
        let reader = try PreparedPCMWindowReader(prepared: prepared)
        let mapper = SpeakerWindowMapper()
        let session = try runtime.makeDiarizationSession(
            sampleRate: Self.sampleRate
        )
        let step = Self.diarizationWindowFrames - Self.diarizationOverlapFrames
        var windowStart: AVAudioFramePosition = 0

        while windowStart < reader.frameCount {
            try Task.checkCancellation()
            let samples = try reader.read(
                from: windowStart,
                count: Self.diarizationWindowFrames
            )
            guard !samples.isEmpty else { break }

            let offset = TimeInterval(windowStart) / TimeInterval(Self.sampleRate)
            let relativeTurns = try session.process(samples)
            let embeddings = session.embeddings(
                for: relativeTurns,
                in: samples
            )
            let localTurns = relativeTurns.map {
                SherpaSpeakerTurn(
                    start: $0.start + offset,
                    end: $0.end + offset,
                    speaker: $0.speaker
                )
            }
            let isFinalWindow =
                windowStart + AVAudioFramePosition(samples.count) >= reader.frameCount
            let commitEnd = isFinalWindow
                ? TimeInterval(reader.frameCount) / TimeInterval(Self.sampleRate)
                : TimeInterval(windowStart + step) / TimeInterval(Self.sampleRate)
            mapper.consume(
                localTurns,
                commitRange: offset..<commitEnd,
                embeddings: embeddings
            )

            if isFinalWindow { break }
            windowStart += step
            await Task.yield()
        }

        return mapper.finish()
    }

    static func assignSpeakers(
        to drafts: [TranscriptDraft],
        from turns: [SherpaSpeakerTurn]
    ) -> [TranscriptDraft] {
        drafts.map { draft in
            let start = draft.startTime
            let end = start + draft.duration
            let speaker = turns
                .map { turn in
                    (
                        speaker: turn.speaker,
                        overlap: max(0, min(end, turn.end) - max(start, turn.start))
                    )
                }
                .filter { $0.overlap > 0 }
                .reduce(into: [Int: TimeInterval]()) {
                    $0[$1.speaker, default: 0] += $1.overlap
                }
                .max {
                    if $0.value == $1.value {
                        return $0.key > $1.key
                    }
                    return $0.value < $1.value
                }?
                .key

            return TranscriptDraft(
                startTime: draft.startTime,
                duration: draft.duration,
                text: draft.text,
                speakerIndex: speaker
            )
        }
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

private final class PreparedPCMWindowReader {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    let frameCount: AVAudioFramePosition

    init(prepared: PreparedPCMFile) throws {
        file = try AVAudioFile(forReading: prepared.url)
        format = file.processingFormat
        frameCount = file.length
        guard
            format.sampleRate == AudioPCMPreparer.outputSampleRate,
            format.channelCount == AudioPCMPreparer.outputChannelCount,
            format.commonFormat == .pcmFormatFloat32
        else {
            throw StayWordError.invalidAudioFile
        }
    }

    func read(
        from startFrame: AVAudioFramePosition,
        count requestedCount: AVAudioFramePosition
    ) throws -> [Float] {
        guard startFrame >= 0, startFrame < frameCount else { return [] }
        let count = min(requestedCount, frameCount - startFrame)
        guard
            let capacity = AVAudioFrameCount(exactly: count),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: capacity
            )
        else {
            throw StayWordError.invalidAudioFile
        }

        file.framePosition = startFrame
        try file.read(into: buffer, frameCount: capacity)
        guard
            buffer.frameLength > 0,
            let channel = buffer.floatChannelData?[0]
        else {
            return []
        }
        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            )
        )
    }
}

final class SpeakerWindowMapper {
    private struct SpeakerProfile {
        var centroid: [Float]
        var observationCount: Int
    }

    private static let embeddingSimilarityThreshold: Float = 0.55

    private var committed: [SherpaSpeakerTurn] = []
    private var previousWindow: [SherpaSpeakerTurn] = []
    private var profiles: [Int: SpeakerProfile] = [:]
    private var nextSpeaker = 0

    func consume(
        _ localTurns: [SherpaSpeakerTurn],
        commitRange: Range<TimeInterval>,
        embeddings: [Int: [Float]] = [:]
    ) {
        let mapping = speakerMapping(
            for: localTurns,
            embeddings: embeddings
        )
        let mapped = localTurns.map {
            SherpaSpeakerTurn(
                start: $0.start,
                end: $0.end,
                speaker: mapping[$0.speaker] ?? allocateSpeaker()
            )
        }

        for turn in mapped {
            let start = max(turn.start, commitRange.lowerBound)
            let end = min(turn.end, commitRange.upperBound)
            guard end > start else { continue }
            appendCommitted(
                SherpaSpeakerTurn(
                    start: start,
                    end: end,
                    speaker: turn.speaker
                )
            )
        }
        updateProfiles(mapping: mapping, embeddings: embeddings)
        if !mapped.isEmpty {
            previousWindow = mapped
        }
    }

    func finish() -> [SherpaSpeakerTurn] {
        committed
    }

    private func speakerMapping(
        for localTurns: [SherpaSpeakerTurn],
        embeddings: [Int: [Float]]
    ) -> [Int: Int] {
        var mapping: [Int: Int] = [:]
        var usedGlobalSpeakers = Set<Int>()
        let localSpeakers = Set(localTurns.map(\.speaker)).sorted()

        for localSpeaker in localSpeakers {
            let candidates = previousWindow.reduce(into: [Int: TimeInterval]()) {
                totals,
                previous in
                let overlap = localTurns
                    .lazy
                    .filter { $0.speaker == localSpeaker }
                    .reduce(0.0) {
                        $0 + max(
                            0,
                            min($1.end, previous.end) - max($1.start, previous.start)
                        )
                    }
                totals[previous.speaker, default: 0] += overlap
            }
            if let match = candidates
                .filter({ $0.value > 0 && !usedGlobalSpeakers.contains($0.key) })
                .max(by: { $0.value < $1.value })?
                .key {
                mapping[localSpeaker] = match
                usedGlobalSpeakers.insert(match)
            }
        }

        for localSpeaker in localSpeakers where mapping[localSpeaker] == nil {
            guard let embedding = embeddings[localSpeaker] else { continue }
            let match = profiles
                .filter { !usedGlobalSpeakers.contains($0.key) }
                .compactMap { globalSpeaker, profile -> (Int, Float)? in
                    guard
                        let similarity = Self.cosineSimilarity(
                            embedding,
                            profile.centroid
                        ),
                        similarity >= Self.embeddingSimilarityThreshold
                    else {
                        return nil
                    }
                    return (globalSpeaker, similarity)
                }
                .max { $0.1 < $1.1 }?
                .0
            if let match {
                mapping[localSpeaker] = match
                usedGlobalSpeakers.insert(match)
            }
        }

        if localSpeakers.count == 1,
           mapping.isEmpty,
           Set(previousWindow.map(\.speaker)).count == 1,
           let previousSpeaker = previousWindow.first?.speaker {
            mapping[localSpeakers[0]] = previousSpeaker
            usedGlobalSpeakers.insert(previousSpeaker)
        }

        let unmatchedLocalSpeakers = localSpeakers.filter {
            mapping[$0] == nil
        }
        let unmatchedPreviousSpeakers = Set(previousWindow.map(\.speaker))
            .subtracting(usedGlobalSpeakers)
        if unmatchedLocalSpeakers.count == 1,
           unmatchedPreviousSpeakers.count == 1,
           let localSpeaker = unmatchedLocalSpeakers.first,
           let previousSpeaker = unmatchedPreviousSpeakers.first {
            mapping[localSpeaker] = previousSpeaker
            usedGlobalSpeakers.insert(previousSpeaker)
        }

        for localSpeaker in localSpeakers where mapping[localSpeaker] == nil {
            let speaker = allocateSpeaker()
            mapping[localSpeaker] = speaker
            usedGlobalSpeakers.insert(speaker)
        }
        return mapping
    }

    private func updateProfiles(
        mapping: [Int: Int],
        embeddings: [Int: [Float]]
    ) {
        for (localSpeaker, embedding) in embeddings {
            guard
                let globalSpeaker = mapping[localSpeaker],
                let normalized = Self.normalized(embedding)
            else {
                continue
            }

            if let existing = profiles[globalSpeaker],
               existing.centroid.count == normalized.count {
                let count = Float(existing.observationCount)
                let combined = zip(existing.centroid, normalized).map {
                    ($0.0 * count + $0.1) / (count + 1)
                }
                profiles[globalSpeaker] = SpeakerProfile(
                    centroid: Self.normalized(combined) ?? normalized,
                    observationCount: existing.observationCount + 1
                )
            } else {
                profiles[globalSpeaker] = SpeakerProfile(
                    centroid: normalized,
                    observationCount: 1
                )
            }
        }
    }

    private static func cosineSimilarity(
        _ lhs: [Float],
        _ rhs: [Float]
    ) -> Float? {
        guard
            lhs.count == rhs.count,
            let normalizedLHS = normalized(lhs),
            let normalizedRHS = normalized(rhs)
        else {
            return nil
        }
        return zip(normalizedLHS, normalizedRHS).reduce(0) {
            $0 + $1.0 * $1.1
        }
    }

    private static func normalized(_ vector: [Float]) -> [Float]? {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude.isFinite, magnitude > 0 else { return nil }
        return vector.map { $0 / magnitude }
    }

    private func allocateSpeaker() -> Int {
        defer { nextSpeaker += 1 }
        return nextSpeaker
    }

    private func appendCommitted(_ turn: SherpaSpeakerTurn) {
        if let last = committed.last,
           last.speaker == turn.speaker,
           turn.start - last.end <= 0.02 {
            committed[committed.count - 1] = SherpaSpeakerTurn(
                start: last.start,
                end: max(last.end, turn.end),
                speaker: last.speaker
            )
        } else {
            committed.append(turn)
        }
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
