import Foundation

struct SherpaStreamingTranscript: Sendable, Equatable {
    let startSample: Int64
    let endSample: Int64
    let text: String
}

enum SherpaOnnxRuntimeError: LocalizedError, Sendable {
    case missingModel(String)
    case unsupportedSampleRate(expected: Int32, actual: Int32)
    case tooManySamples
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
        case let .initializationFailed(component):
            "The on-device \(component) model could not be initialized."
        case let .processingFailed(component):
            "The on-device \(component) model could not process this audio."
        }
    }
}

/// Minimal, synchronous facade around the sherpa-onnx v1.13.2 C API.
///
/// The caller serializes access through `TranscriptionService`. One bounded
/// streaming session performs both voice activity detection and recognition.
struct SherpaOnnxRuntime: Sendable {
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

        static let senseVoiceLanguage = "zh"
        static let decodingMethod = "greedy_search"
    }

    fileprivate struct ModelPaths: Sendable {
        let sileroVAD: String
        let senseVoice: String
        let senseVoiceTokens: String

        init(bundle: Bundle) throws {
            sileroVAD = try Self.requiredResource(
                named: "silero_vad",
                extension: "onnx",
                subdirectory: "Models/VAD",
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

    private func validate(sampleRate: Int32) throws {
        guard sampleRate == Constants.requiredSampleRate else {
            throw SherpaOnnxRuntimeError.unsupportedSampleRate(
                expected: Constants.requiredSampleRate,
                actual: sampleRate
            )
        }
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
