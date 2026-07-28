import Foundation

struct SherpaSpeechInterval: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
}

struct SherpaSpeakerTurn: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let speaker: Int
}

struct SherpaStreamingTranscript: Sendable, Equatable {
    let startSample: Int64
    let endSample: Int64
    let text: String
}

enum SherpaOnnxRuntimeError: LocalizedError, Sendable {
    case missingModel(String)
    case unsupportedSampleRate(expected: Int32, actual: Int32)
    case tooManySamples
    case invalidSampleRange(lowerBound: Int, upperBound: Int)
    case initializationFailed(String)
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingModel(relativePath):
            "The bundled transcription model is missing: \(relativePath)"
        case let .unsupportedSampleRate(expected, actual):
            "The transcription models require \(expected) Hz audio, but received \(actual) Hz."
        case .tooManySamples:
            "The audio segment is too large for the on-device transcription runtime."
        case let .invalidSampleRange(lowerBound, upperBound):
            "The transcription sample range is invalid: \(lowerBound)..<\(upperBound)."
        case let .initializationFailed(component):
            "The on-device \(component) model could not be initialized."
        case let .processingFailed(component):
            "The on-device \(component) model could not process this audio."
        }
    }
}

/// Minimal, synchronous facade around the sherpa-onnx v1.13.2 C API.
///
/// The caller is expected to serialize calls (the concrete `TranscriptionService`
/// actor does this). Streaming VAD and ASR share one bounded session; that
/// session is released before the windowed diarization model is loaded.
struct SherpaOnnxRuntime: Sendable {
    /// Increment when clustering parameters or diarization models change.
    static let diarizationProfileVersion = 2

    private enum Constants {
        static let requiredSampleRate: Int32 = 16_000
        static let inferenceThreads: Int32 = 2
        static let provider = "cpu"

        static let vadWindowSize = 512
        static let vadThreshold: Float = 0.5
        static let vadMinimumSilenceDuration: Float = 0.35
        static let vadMinimumSpeechDuration: Float = 0.2
        static let vadMaximumSpeechDuration: Float = 30
        static let vadBufferSizeInSeconds: Float = 60

        /// `num_clusters = -1` enables threshold-based automatic speaker count.
        /// This value belongs to diarization profile v1 and should be calibrated
        /// as a versioned model parameter rather than exposed as a user setting.
        static let automaticSpeakerClusteringThreshold: Float = 0.8
        static let diarizationMinimumOnDuration: Float = 0.2
        static let diarizationMinimumOffDuration: Float = 0.5

        static let senseVoiceLanguage = "auto"
        static let decodingMethod = "greedy_search"
    }

    fileprivate struct ModelPaths: Sendable {
        let sileroVAD: String
        let pyannote: String
        let speakerEmbedding: String
        let senseVoice: String
        let senseVoiceTokens: String

        init(bundle: Bundle) throws {
            sileroVAD = try Self.requiredResource(
                named: "silero_vad",
                extension: "onnx",
                subdirectory: "Models/VAD",
                bundle: bundle
            )
            pyannote = try Self.requiredResource(
                named: "model.int8",
                extension: "onnx",
                subdirectory: "Models/Pyannote",
                bundle: bundle
            )
            speakerEmbedding = try Self.requiredResource(
                named: "3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k",
                extension: "onnx",
                subdirectory: "Models/SpeakerEmbedding",
                bundle: bundle
            )
            senseVoice = try Self.requiredResource(
                named: "model.int8",
                extension: "onnx",
                subdirectory: "Models/SenseVoice",
                bundle: bundle
            )
            senseVoiceTokens = try Self.requiredResource(
                named: "tokens",
                extension: "txt",
                subdirectory: "Models/SenseVoice",
                bundle: bundle
            )
        }

        private static func requiredResource(
            named name: String,
            extension fileExtension: String,
            subdirectory: String,
            bundle: Bundle
        ) throws -> String {
            let relativePath = "\(subdirectory)/\(name).\(fileExtension)"
            guard
                let url = bundle.url(
                    forResource: name,
                    withExtension: fileExtension,
                    subdirectory: subdirectory
                ),
                FileManager.default.isReadableFile(atPath: url.path)
            else {
                throw SherpaOnnxRuntimeError.missingModel(relativePath)
            }
            return url.path
        }
    }

    private let models: ModelPaths

    init(bundle: Bundle = .main) throws {
        models = try ModelPaths(bundle: bundle)
    }

    func makeStreamingRecognizer(
        sampleRate: Int32,
        baseSampleOffset: Int64 = 0
    ) throws -> StreamingRecognizer {
        try validate(sampleRate: sampleRate)
        return try StreamingRecognizer(
            models: models,
            sampleRate: sampleRate,
            baseSampleOffset: baseSampleOffset
        )
    }

    func makeDiarizationSession(sampleRate: Int32) throws -> DiarizationSession {
        try validate(sampleRate: sampleRate)
        return try DiarizationSession(models: models, sampleRate: sampleRate)
    }

    final class StreamingRecognizer {
        private let detector: OpaquePointer
        private let recognizer: OpaquePointer
        private let sampleRate: Int32
        private let baseSampleOffset: Int64
        private var pendingSamples: [Float] = []
        private var isFinished = false

        fileprivate init(
            models: ModelPaths,
            sampleRate: Int32,
            baseSampleOffset: Int64
        ) throws {
            self.sampleRate = sampleRate
            self.baseSampleOffset = max(0, baseSampleOffset)

            detector = try Self.makeDetector(
                modelPath: models.sileroVAD,
                sampleRate: sampleRate
            )
            do {
                recognizer = try Self.makeRecognizer(models: models)
            } catch {
                SherpaOnnxDestroyVoiceActivityDetector(detector)
                throw error
            }
        }

        deinit {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
            SherpaOnnxDestroyVoiceActivityDetector(detector)
        }

        func accept(_ samples: [Float]) throws -> [SherpaStreamingTranscript] {
            guard !isFinished, !samples.isEmpty else { return [] }
            pendingSamples.append(contentsOf: samples)

            let consumableCount =
                pendingSamples.count / Constants.vadWindowSize * Constants.vadWindowSize
            guard consumableCount > 0 else { return [] }

            var results: [SherpaStreamingTranscript] = []
            try pendingSamples.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                var offset = 0
                while offset < consumableCount {
                    SherpaOnnxVoiceActivityDetectorAcceptWaveform(
                        detector,
                        baseAddress.advanced(by: offset),
                        Int32(Constants.vadWindowSize)
                    )
                    offset += Constants.vadWindowSize
                    results.append(contentsOf: try drainCompletedSegments())
                }
            }

            pendingSamples = Array(pendingSamples.dropFirst(consumableCount))
            return results
        }

        func finish() throws -> [SherpaStreamingTranscript] {
            guard !isFinished else { return [] }
            isFinished = true

            var results: [SherpaStreamingTranscript] = []
            if !pendingSamples.isEmpty {
                var finalWindow = pendingSamples
                finalWindow.append(
                    contentsOf: repeatElement(
                        0,
                        count: Constants.vadWindowSize - finalWindow.count
                    )
                )
                finalWindow.withUnsafeBufferPointer { buffer in
                    SherpaOnnxVoiceActivityDetectorAcceptWaveform(
                        detector,
                        buffer.baseAddress,
                        Int32(Constants.vadWindowSize)
                    )
                }
                pendingSamples.removeAll(keepingCapacity: false)
                results.append(contentsOf: try drainCompletedSegments())
            }

            SherpaOnnxVoiceActivityDetectorFlush(detector)
            results.append(contentsOf: try drainCompletedSegments())
            return results
        }

        private func drainCompletedSegments() throws -> [SherpaStreamingTranscript] {
            var results: [SherpaStreamingTranscript] = []
            while SherpaOnnxVoiceActivityDetectorEmpty(detector) == 0 {
                guard let segment = SherpaOnnxVoiceActivityDetectorFront(detector) else {
                    throw SherpaOnnxRuntimeError.processingFailed("speech detection")
                }
                defer {
                    SherpaOnnxDestroySpeechSegment(segment)
                    SherpaOnnxVoiceActivityDetectorPop(detector)
                }

                let start = max(0, Int64(segment.pointee.start))
                let count = max(0, Int(segment.pointee.n))
                let text: String
                if count > 0, let samples = segment.pointee.samples {
                    text = try recognize(samples: samples, count: count)
                } else {
                    text = ""
                }

                let absoluteStart = baseSampleOffset + start
                results.append(
                    SherpaStreamingTranscript(
                        startSample: absoluteStart,
                        endSample: absoluteStart + Int64(count),
                        text: text
                    )
                )
            }
            return results
        }

        private func recognize(
            samples: UnsafePointer<Float>,
            count: Int
        ) throws -> String {
            guard let count = Int32(exactly: count) else {
                throw SherpaOnnxRuntimeError.tooManySamples
            }
            guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
                throw SherpaOnnxRuntimeError.initializationFailed(
                    "speech recognition stream"
                )
            }
            defer {
                SherpaOnnxDestroyOfflineStream(stream)
            }

            SherpaOnnxAcceptWaveformOffline(stream, sampleRate, samples, count)
            SherpaOnnxDecodeOfflineStream(recognizer, stream)
            guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
                throw SherpaOnnxRuntimeError.processingFailed("speech recognition")
            }
            defer {
                SherpaOnnxDestroyOfflineRecognizerResult(result)
            }
            guard let rawText = result.pointee.text else { return "" }
            return SherpaOnnxRuntime.cleanedSenseVoiceText(String(cString: rawText))
        }

        private static func makeDetector(
            modelPath: String,
            sampleRate: Int32
        ) throws -> OpaquePointer {
            try modelPath.withCString { modelPath in
                try Constants.provider.withCString { provider in
                    var config = SherpaOnnxVadModelConfig()
                    config.silero_vad.model = modelPath
                    config.silero_vad.threshold = Constants.vadThreshold
                    config.silero_vad.min_silence_duration =
                        Constants.vadMinimumSilenceDuration
                    config.silero_vad.min_speech_duration =
                        Constants.vadMinimumSpeechDuration
                    config.silero_vad.window_size = Int32(Constants.vadWindowSize)
                    config.silero_vad.max_speech_duration =
                        Constants.vadMaximumSpeechDuration
                    config.sample_rate = sampleRate
                    config.num_threads = Constants.inferenceThreads
                    config.provider = provider
                    config.debug = 0

                    guard let detector = SherpaOnnxCreateVoiceActivityDetector(
                        &config,
                        Constants.vadBufferSizeInSeconds
                    ) else {
                        throw SherpaOnnxRuntimeError.initializationFailed(
                            "speech detection"
                        )
                    }
                    return detector
                }
            }
        }

        private static func makeRecognizer(models: ModelPaths) throws -> OpaquePointer {
            try models.senseVoice.withCString { modelPath in
                try models.senseVoiceTokens.withCString { tokensPath in
                    try Constants.senseVoiceLanguage.withCString { language in
                        try Constants.provider.withCString { provider in
                            try Constants.decodingMethod.withCString { decodingMethod in
                                var config = SherpaOnnxOfflineRecognizerConfig()
                                config.feat_config.sample_rate =
                                    Constants.requiredSampleRate
                                config.feat_config.feature_dim = 80
                                config.model_config.tokens = tokensPath
                                config.model_config.num_threads =
                                    Constants.inferenceThreads
                                config.model_config.debug = 0
                                config.model_config.provider = provider
                                config.model_config.sense_voice.model = modelPath
                                config.model_config.sense_voice.language = language
                                config.model_config.sense_voice.use_itn = 1
                                config.decoding_method = decodingMethod
                                config.max_active_paths = 4

                                guard let recognizer =
                                    SherpaOnnxCreateOfflineRecognizer(&config)
                                else {
                                    throw SherpaOnnxRuntimeError.initializationFailed(
                                        "speech recognition"
                                    )
                                }
                                return recognizer
                            }
                        }
                    }
                }
            }
        }
    }

    final class DiarizationSession {
        private let diarizer: OpaquePointer
        private let embeddingExtractor: OpaquePointer
        private let embeddingDimension: Int
        private let sampleRate: Int32

        fileprivate init(models: ModelPaths, sampleRate: Int32) throws {
            self.sampleRate = sampleRate
            diarizer = try models.pyannote.withCString { pyannotePath in
                try models.speakerEmbedding.withCString { embeddingPath in
                    try Constants.provider.withCString { provider in
                        var config = SherpaOnnxOfflineSpeakerDiarizationConfig()
                        config.segmentation.pyannote.model = pyannotePath
                        config.segmentation.num_threads =
                            Constants.inferenceThreads
                        config.segmentation.debug = 0
                        config.segmentation.provider = provider
                        config.embedding.model = embeddingPath
                        config.embedding.num_threads = Constants.inferenceThreads
                        config.embedding.debug = 0
                        config.embedding.provider = provider
                        config.clustering.num_clusters = -1
                        config.clustering.threshold =
                            Constants.automaticSpeakerClusteringThreshold
                        config.min_duration_on =
                            Constants.diarizationMinimumOnDuration
                        config.min_duration_off =
                            Constants.diarizationMinimumOffDuration

                        guard let diarizer =
                            SherpaOnnxCreateOfflineSpeakerDiarization(&config)
                        else {
                            throw SherpaOnnxRuntimeError.initializationFailed(
                                "speaker diarization"
                            )
                        }
                        return diarizer
                    }
                }
            }

            let expectedSampleRate =
                SherpaOnnxOfflineSpeakerDiarizationGetSampleRate(diarizer)
            guard expectedSampleRate == sampleRate else {
                SherpaOnnxDestroyOfflineSpeakerDiarization(diarizer)
                throw SherpaOnnxRuntimeError.unsupportedSampleRate(
                    expected: expectedSampleRate,
                    actual: sampleRate
                )
            }

            do {
                embeddingExtractor = try models.speakerEmbedding.withCString {
                    modelPath in
                    try Constants.provider.withCString { provider in
                        var config = SherpaOnnxSpeakerEmbeddingExtractorConfig()
                        config.model = modelPath
                        config.num_threads = Constants.inferenceThreads
                        config.debug = 0
                        config.provider = provider
                        guard let extractor =
                            SherpaOnnxCreateSpeakerEmbeddingExtractor(&config)
                        else {
                            throw SherpaOnnxRuntimeError.initializationFailed(
                                "speaker embedding"
                            )
                        }
                        return extractor
                    }
                }
            } catch {
                SherpaOnnxDestroyOfflineSpeakerDiarization(diarizer)
                throw error
            }
            embeddingDimension = Int(
                SherpaOnnxSpeakerEmbeddingExtractorDim(embeddingExtractor)
            )
            guard embeddingDimension > 0 else {
                SherpaOnnxDestroySpeakerEmbeddingExtractor(embeddingExtractor)
                SherpaOnnxDestroyOfflineSpeakerDiarization(diarizer)
                throw SherpaOnnxRuntimeError.initializationFailed(
                    "speaker embedding"
                )
            }
        }

        deinit {
            SherpaOnnxDestroySpeakerEmbeddingExtractor(embeddingExtractor)
            SherpaOnnxDestroyOfflineSpeakerDiarization(diarizer)
        }

        func process(_ samples: [Float]) throws -> [SherpaSpeakerTurn] {
            guard !samples.isEmpty else { return [] }
            guard let sampleCount = Int32(exactly: samples.count) else {
                throw SherpaOnnxRuntimeError.tooManySamples
            }

            return try samples.withUnsafeBufferPointer { buffer in
                guard
                    let baseAddress = buffer.baseAddress,
                    let result = SherpaOnnxOfflineSpeakerDiarizationProcess(
                        diarizer,
                        baseAddress,
                        sampleCount
                    )
                else {
                    throw SherpaOnnxRuntimeError.processingFailed(
                        "speaker diarization"
                    )
                }
                defer {
                    SherpaOnnxOfflineSpeakerDiarizationDestroyResult(result)
                }

                let segmentCount = Int(
                    SherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments(
                        result
                    )
                )
                guard segmentCount > 0 else { return [] }
                guard let segments =
                    SherpaOnnxOfflineSpeakerDiarizationResultSortByStartTime(
                        result
                    )
                else {
                    throw SherpaOnnxRuntimeError.processingFailed(
                        "speaker diarization"
                    )
                }
                defer {
                    SherpaOnnxOfflineSpeakerDiarizationDestroySegment(segments)
                }

                var turns: [SherpaSpeakerTurn] = []
                turns.reserveCapacity(segmentCount)
                for index in 0..<segmentCount {
                    let segment = segments[index]
                    let start = TimeInterval(segment.start)
                    let end = TimeInterval(segment.end)
                    guard
                        start.isFinite,
                        end.isFinite,
                        start >= 0,
                        end > start,
                        segment.speaker >= 0
                    else {
                        continue
                    }
                    turns.append(
                        SherpaSpeakerTurn(
                            start: start,
                            end: end,
                            speaker: Int(segment.speaker)
                        )
                    )
                }
                return turns
            }
        }

        func embeddings(
            for turns: [SherpaSpeakerTurn],
            in samples: [Float],
            maximumSecondsPerSpeaker: TimeInterval = 12
        ) -> [Int: [Float]] {
            let maximumSamples = max(
                1,
                Int(maximumSecondsPerSpeaker * TimeInterval(sampleRate))
            )
            var results: [Int: [Float]] = [:]

            for speaker in Set(turns.map(\.speaker)).sorted() {
                var voice: [Float] = []
                voice.reserveCapacity(maximumSamples)
                for turn in turns where turn.speaker == speaker {
                    let lower = max(
                        0,
                        min(
                            samples.count,
                            Int((turn.start * TimeInterval(sampleRate)).rounded(.down))
                        )
                    )
                    let upper = max(
                        lower,
                        min(
                            samples.count,
                            Int((turn.end * TimeInterval(sampleRate)).rounded(.up))
                        )
                    )
                    let available = min(
                        upper - lower,
                        maximumSamples - voice.count
                    )
                    guard available > 0 else { continue }
                    voice.append(contentsOf: samples[lower..<(lower + available)])
                    if voice.count >= maximumSamples { break }
                }

                guard let embedding = embedding(for: voice) else { continue }
                results[speaker] = embedding
            }
            return results
        }

        private func embedding(for samples: [Float]) -> [Float]? {
            guard
                !samples.isEmpty,
                let count = Int32(exactly: samples.count),
                let stream =
                    SherpaOnnxSpeakerEmbeddingExtractorCreateStream(
                        embeddingExtractor
                    )
            else {
                return nil
            }
            defer {
                SherpaOnnxDestroyOnlineStream(stream)
            }

            samples.withUnsafeBufferPointer { buffer in
                SherpaOnnxOnlineStreamAcceptWaveform(
                    stream,
                    sampleRate,
                    buffer.baseAddress,
                    count
                )
            }
            SherpaOnnxOnlineStreamInputFinished(stream)
            guard
                SherpaOnnxSpeakerEmbeddingExtractorIsReady(
                    embeddingExtractor,
                    stream
                ) == 1,
                let vector =
                    SherpaOnnxSpeakerEmbeddingExtractorComputeEmbedding(
                        embeddingExtractor,
                        stream
                    )
            else {
                return nil
            }
            defer {
                SherpaOnnxSpeakerEmbeddingExtractorDestroyEmbedding(vector)
            }
            return Array(
                UnsafeBufferPointer(
                    start: vector,
                    count: embeddingDimension
                )
            )
        }
    }

    func detectSpeech(
        samples: [Float],
        sampleRate: Int32
    ) throws -> [SherpaSpeechInterval] {
        try validate(sampleRate: sampleRate)
        guard !samples.isEmpty else {
            return []
        }

        return try models.sileroVAD.withCString { modelPath in
            try Constants.provider.withCString { provider in
                var config = SherpaOnnxVadModelConfig()
                config.silero_vad.model = modelPath
                config.silero_vad.threshold = Constants.vadThreshold
                config.silero_vad.min_silence_duration =
                    Constants.vadMinimumSilenceDuration
                config.silero_vad.min_speech_duration =
                    Constants.vadMinimumSpeechDuration
                config.silero_vad.window_size = Int32(Constants.vadWindowSize)
                config.silero_vad.max_speech_duration =
                    Constants.vadMaximumSpeechDuration
                config.sample_rate = sampleRate
                config.num_threads = Constants.inferenceThreads
                config.provider = provider
                config.debug = 0

                guard let detector = SherpaOnnxCreateVoiceActivityDetector(
                    &config,
                    Constants.vadBufferSizeInSeconds
                ) else {
                    throw SherpaOnnxRuntimeError.initializationFailed(
                        "speech detection"
                    )
                }
                defer {
                    SherpaOnnxDestroyVoiceActivityDetector(detector)
                }

                var intervals: [SherpaSpeechInterval] = []
                let audioDuration = TimeInterval(samples.count) / TimeInterval(sampleRate)

                func drainCompletedSegments() throws {
                    while SherpaOnnxVoiceActivityDetectorEmpty(detector) == 0 {
                        guard let segment = SherpaOnnxVoiceActivityDetectorFront(detector) else {
                            throw SherpaOnnxRuntimeError.processingFailed(
                                "speech detection"
                            )
                        }

                        let startSample = max(0, Int(segment.pointee.start))
                        let sampleCount = max(0, Int(segment.pointee.n))
                        SherpaOnnxDestroySpeechSegment(segment)
                        SherpaOnnxVoiceActivityDetectorPop(detector)

                        let start = min(
                            TimeInterval(startSample) / TimeInterval(sampleRate),
                            audioDuration
                        )
                        let end = min(
                            TimeInterval(startSample + sampleCount)
                                / TimeInterval(sampleRate),
                            audioDuration
                        )
                        if end > start {
                            intervals.append(
                                SherpaSpeechInterval(start: start, end: end)
                            )
                        }
                    }
                }

                try samples.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else {
                        return
                    }

                    var offset = 0
                    while offset + Constants.vadWindowSize <= samples.count {
                        SherpaOnnxVoiceActivityDetectorAcceptWaveform(
                            detector,
                            baseAddress.advanced(by: offset),
                            Int32(Constants.vadWindowSize)
                        )
                        offset += Constants.vadWindowSize
                        try drainCompletedSegments()
                    }

                    if offset < samples.count {
                        var finalWindow = [Float](
                            repeating: 0,
                            count: Constants.vadWindowSize
                        )
                        finalWindow.withUnsafeMutableBufferPointer { destination in
                            guard let destinationBase = destination.baseAddress else {
                                return
                            }
                            destinationBase.update(
                                from: baseAddress.advanced(by: offset),
                                count: samples.count - offset
                            )
                        }
                        finalWindow.withUnsafeBufferPointer { finalBuffer in
                            SherpaOnnxVoiceActivityDetectorAcceptWaveform(
                                detector,
                                finalBuffer.baseAddress,
                                Int32(Constants.vadWindowSize)
                            )
                        }
                        try drainCompletedSegments()
                    }
                }

                SherpaOnnxVoiceActivityDetectorFlush(detector)
                try drainCompletedSegments()
                return Self.mergedIntervals(intervals)
            }
        }
    }

    func diarize(
        samples: [Float],
        sampleRate: Int32
    ) throws -> [SherpaSpeakerTurn] {
        try makeDiarizationSession(sampleRate: sampleRate).process(samples)
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int32
    ) throws -> String {
        guard !samples.isEmpty else {
            return ""
        }
        return try transcribe(
            ranges: [samples.startIndex..<samples.endIndex],
            in: samples,
            sampleRate: sampleRate
        )[0]
    }

    /// Transcribes source-buffer ranges sequentially while keeping one
    /// SenseVoice recognizer loaded for the complete batch.
    func transcribe(
        ranges: [Range<Int>],
        in samples: [Float],
        sampleRate: Int32
    ) throws -> [String] {
        try validate(sampleRate: sampleRate)
        guard !ranges.isEmpty else {
            return []
        }

        for range in ranges {
            guard
                range.lowerBound >= samples.startIndex,
                range.upperBound <= samples.endIndex,
                range.lowerBound <= range.upperBound
            else {
                throw SherpaOnnxRuntimeError.invalidSampleRange(
                    lowerBound: range.lowerBound,
                    upperBound: range.upperBound
                )
            }
            guard Int32(exactly: range.count) != nil else {
                throw SherpaOnnxRuntimeError.tooManySamples
            }
        }

        return try withSenseVoiceRecognizer { recognizer in
            try samples.withUnsafeBufferPointer { buffer in
                var texts: [String] = []
                texts.reserveCapacity(ranges.count)

                for range in ranges {
                    guard !range.isEmpty else {
                        texts.append("")
                        continue
                    }
                    guard
                        let baseAddress = buffer.baseAddress,
                        let rangeCount = Int32(exactly: range.count)
                    else {
                        throw SherpaOnnxRuntimeError.tooManySamples
                    }

                    guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
                        throw SherpaOnnxRuntimeError.initializationFailed(
                            "speech recognition stream"
                        )
                    }

                    let text: String
                    do {
                        SherpaOnnxAcceptWaveformOffline(
                            stream,
                            sampleRate,
                            baseAddress.advanced(by: range.lowerBound),
                            rangeCount
                        )
                        SherpaOnnxDecodeOfflineStream(recognizer, stream)
                        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
                            throw SherpaOnnxRuntimeError.processingFailed(
                                "speech recognition"
                            )
                        }
                        defer {
                            SherpaOnnxDestroyOfflineRecognizerResult(result)
                        }

                        if let rawText = result.pointee.text {
                            text = Self.cleanedSenseVoiceText(
                                String(cString: rawText)
                            )
                        } else {
                            text = ""
                        }
                    } catch {
                        SherpaOnnxDestroyOfflineStream(stream)
                        throw error
                    }

                    SherpaOnnxDestroyOfflineStream(stream)
                    texts.append(text)
                }
                return texts
            }
        }
    }

    private func withSenseVoiceRecognizer<Result>(
        _ body: (OpaquePointer) throws -> Result
    ) throws -> Result {
        try models.senseVoice.withCString { modelPath in
            try models.senseVoiceTokens.withCString { tokensPath in
                try Constants.senseVoiceLanguage.withCString { language in
                    try Constants.provider.withCString { provider in
                        try Constants.decodingMethod.withCString { decodingMethod in
                            var config = SherpaOnnxOfflineRecognizerConfig()
                            config.feat_config.sample_rate =
                                Constants.requiredSampleRate
                            config.feat_config.feature_dim = 80
                            config.model_config.tokens = tokensPath
                            config.model_config.num_threads =
                                Constants.inferenceThreads
                            config.model_config.debug = 0
                            config.model_config.provider = provider
                            config.model_config.sense_voice.model = modelPath
                            config.model_config.sense_voice.language = language
                            config.model_config.sense_voice.use_itn = 1
                            config.decoding_method = decodingMethod
                            config.max_active_paths = 4

                            guard let recognizer =
                                SherpaOnnxCreateOfflineRecognizer(&config)
                            else {
                                throw SherpaOnnxRuntimeError.initializationFailed(
                                    "speech recognition"
                                )
                            }
                            defer {
                                SherpaOnnxDestroyOfflineRecognizer(recognizer)
                            }
                            return try body(recognizer)
                        }
                    }
                }
            }
        }
    }

    private func validate(sampleRate: Int32) throws {
        guard sampleRate == Constants.requiredSampleRate else {
            throw SherpaOnnxRuntimeError.unsupportedSampleRate(
                expected: Constants.requiredSampleRate,
                actual: sampleRate
            )
        }
    }

    private static func mergedIntervals(
        _ intervals: [SherpaSpeechInterval]
    ) -> [SherpaSpeechInterval] {
        let sorted = intervals.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                lhs.end < rhs.end
            } else {
                lhs.start < rhs.start
            }
        }

        var merged: [SherpaSpeechInterval] = []
        merged.reserveCapacity(sorted.count)
        for interval in sorted {
            guard let last = merged.last, interval.start <= last.end else {
                merged.append(interval)
                continue
            }
            merged[merged.count - 1] = SherpaSpeechInterval(
                start: last.start,
                end: max(last.end, interval.end)
            )
        }
        return merged
    }

    private static func cleanedSenseVoiceText(_ rawText: String) -> String {
        var text = ""
        var cursor = rawText.startIndex

        while
            let markerStart = rawText.range(
                of: "<|",
                range: cursor..<rawText.endIndex
            )
        {
            text.append(contentsOf: rawText[cursor..<markerStart.lowerBound])
            guard
                let markerEnd = rawText.range(
                    of: "|>",
                    range: markerStart.upperBound..<rawText.endIndex
                )
            else {
                text.append(contentsOf: rawText[markerStart.lowerBound...])
                cursor = rawText.endIndex
                break
            }
            cursor = markerEnd.upperBound
        }

        if cursor < rawText.endIndex {
            text.append(contentsOf: rawText[cursor..<rawText.endIndex])
        }

        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
