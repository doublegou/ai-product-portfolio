import AVFAudio
import Foundation

/// A file-backed, normalized PCM stream produced by ``AudioPCMPreparer``.
struct PreparedPCMFile: Sendable {
    struct Metadata: Sendable, Equatable {
        let sampleRate: Double
        let channelCount: Int
        let bitsPerChannel: Int
        let isFloat: Bool
        let isInterleaved: Bool
        let frameCount: Int64
        let duration: TimeInterval
        let byteCount: Int64
    }

    /// The CAF file containing 16 kHz, mono, non-interleaved Float32 PCM.
    let url: URL
    let metadata: Metadata

    /// `true` when the preparer selected a location in the temporary directory.
    let isTemporary: Bool

    /// Removes the prepared file. This operation is idempotent.
    func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

enum AudioPCMPreparerError: LocalizedError, Sendable {
    case destinationMustBeCAF
    case destinationAlreadyExists(URL)
    case invalidSourceFormat
    case cannotCreateTargetFormat
    case cannotCreateConverter
    case cannotAllocateBuffer
    case conversionFailed
    case sourceContainsNoAudio

    var errorDescription: String? {
        switch self {
        case .destinationMustBeCAF:
            String(localized: "The destination must be a file URL with a .caf extension.")
        case let .destinationAlreadyExists(url):
            String(localized: "The PCM destination already exists: \(url.lastPathComponent)")
        case .invalidSourceFormat:
            String(localized: "The source audio format is not valid for PCM conversion.")
        case .cannotCreateTargetFormat:
            String(localized: "The 16 kHz mono Float32 target format could not be created.")
        case .cannotCreateConverter:
            String(localized: "The source audio format cannot be converted to 16 kHz mono PCM.")
        case .cannotAllocateBuffer:
            String(localized: "An audio conversion buffer could not be allocated.")
        case .conversionFailed:
            String(localized: "The audio converter stopped without completing the output stream.")
        case .sourceContainsNoAudio:
            String(localized: "The source file contains no readable audio frames.")
        }
    }
}

/// Streams any format readable by `AVAudioFile` into a normalized, file-backed
/// representation without accumulating the complete recording in memory.
struct AudioPCMPreparer: Sendable {
    static let outputSampleRate: Double = 16_000
    static let outputChannelCount: Int = 1

    private let inputFrameCapacity: AVAudioFrameCount
    private let outputFrameCapacity: AVAudioFrameCount

    init(
        inputFrameCapacity: AVAudioFrameCount = 8_192,
        outputFrameCapacity: AVAudioFrameCount = 4_096
    ) {
        self.inputFrameCapacity = max(256, inputFrameCapacity)
        self.outputFrameCapacity = max(256, outputFrameCapacity)
    }

    /// Opens and prepares a source URL. Cancelling the calling task stops at the
    /// next bounded input chunk and removes any partial destination.
    func prepare(
        contentsOf sourceURL: URL,
        destinationURL: URL? = nil
    ) async throws -> PreparedPCMFile {
        try Task.checkCancellation()
        let sourceFile = try AVAudioFile(forReading: sourceURL)

        return try prepare(
            sourceFile,
            destinationURL: destinationURL,
            isCancelled: {
                withUnsafeCurrentTask { task in
                    task?.isCancelled ?? false
                }
            }
        )
    }

    /// Prepares an already-open file. The file is consumed from its current frame
    /// position. The cancellation closure is checked before every bounded read.
    ///
    /// This synchronous overload is useful when the caller owns an `AVAudioFile`;
    /// keeping that non-Sendable object out of the async API avoids crossing
    /// concurrency domains.
    func prepare(
        _ sourceFile: AVAudioFile,
        destinationURL: URL? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> PreparedPCMFile {
        let destination = try resolvedDestination(destinationURL)
        let destinationWasTemporary = destinationURL == nil

        do {
            try throwIfCancelled(isCancelled)

            let sourceFormat = sourceFile.processingFormat
            guard
                sourceFormat.sampleRate.isFinite,
                sourceFormat.sampleRate > 0,
                sourceFormat.channelCount > 0
            else {
                throw AudioPCMPreparerError.invalidSourceFormat
            }

            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.outputSampleRate,
                channels: AVAudioChannelCount(Self.outputChannelCount),
                interleaved: false
            ) else {
                throw AudioPCMPreparerError.cannotCreateTargetFormat
            }

            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                throw AudioPCMPreparerError.cannotCreateConverter
            }
            converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

            guard
                let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFormat,
                    frameCapacity: inputFrameCapacity
                ),
                let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: outputFrameCapacity
                )
            else {
                throw AudioPCMPreparerError.cannotAllocateBuffer
            }

            var outputFile: AVAudioFile? = try AVAudioFile(
                forWriting: destination,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            let state = ConversionInputState(
                sourceFile: sourceFile,
                inputBuffer: inputBuffer,
                isCancelled: isCancelled
            )

            var totalFrames: Int64 = 0
            var didReachEnd = false

            while !didReachEnd {
                try throwIfCancelled(isCancelled)
                outputBuffer.frameLength = 0

                var converterError: NSError?
                let status = converter.convert(
                    to: outputBuffer,
                    error: &converterError
                ) { requestedPackets, inputStatus in
                    state.nextBuffer(
                        requestedPackets: requestedPackets,
                        status: inputStatus
                    )
                }

                if let readError = state.readError {
                    throw readError
                }
                try throwIfCancelled(isCancelled)

                if outputBuffer.frameLength > 0 {
                    guard let outputFile else {
                        throw AudioPCMPreparerError.conversionFailed
                    }
                    try outputFile.write(from: outputBuffer)
                    totalFrames += Int64(outputBuffer.frameLength)
                }

                switch status {
                case .haveData, .inputRanDry:
                    continue
                case .endOfStream:
                    didReachEnd = true
                case .error:
                    throw converterError ?? AudioPCMPreparerError.conversionFailed
                @unknown default:
                    throw AudioPCMPreparerError.conversionFailed
                }
            }

            try throwIfCancelled(isCancelled)
            guard totalFrames > 0 else {
                throw AudioPCMPreparerError.sourceContainsNoAudio
            }

            // AVAudioFile flushes its encoder/container state when released.
            outputFile = nil

            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let duration = Double(totalFrames) / Self.outputSampleRate

            return PreparedPCMFile(
                url: destination,
                metadata: .init(
                    sampleRate: Self.outputSampleRate,
                    channelCount: Self.outputChannelCount,
                    bitsPerChannel: 32,
                    isFloat: true,
                    isInterleaved: false,
                    frameCount: totalFrames,
                    duration: duration,
                    byteCount: byteCount
                ),
                isTemporary: destinationWasTemporary
            )
        } catch {
            try? removePartialFile(at: destination)
            throw error
        }
    }

    private func resolvedDestination(_ requestedURL: URL?) throws -> URL {
        let url = requestedURL
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioPCM-\(UUID().uuidString)")
                .appendingPathExtension("caf")

        guard url.isFileURL, url.pathExtension.lowercased() == "caf" else {
            throw AudioPCMPreparerError.destinationMustBeCAF
        }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw AudioPCMPreparerError.destinationAlreadyExists(url)
        }
        return url
    }

    private func removePartialFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func throwIfCancelled(
        _ isCancelled: @Sendable () -> Bool
    ) throws {
        if isCancelled() {
            throw CancellationError()
        }
    }
}

/// `AVAudioConverter` invokes its input block synchronously during `convert`.
/// Isolating the mutable callback state here avoids capturing mutable locals in
/// a `@Sendable` framework closure. The instance never escapes `prepare`.
private final class ConversionInputState: @unchecked Sendable {
    private let sourceFile: AVAudioFile
    private let inputBuffer: AVAudioPCMBuffer
    private let isCancelled: @Sendable () -> Bool

    private(set) var readError: Error?
    private var reachedEndOfStream = false

    init(
        sourceFile: AVAudioFile,
        inputBuffer: AVAudioPCMBuffer,
        isCancelled: @escaping @Sendable () -> Bool
    ) {
        self.sourceFile = sourceFile
        self.inputBuffer = inputBuffer
        self.isCancelled = isCancelled
    }

    func nextBuffer(
        requestedPackets: AVAudioPacketCount,
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        if reachedEndOfStream {
            status.pointee = .endOfStream
            return nil
        }
        if isCancelled() {
            status.pointee = .noDataNow
            return nil
        }

        let remainingFrames = sourceFile.length - sourceFile.framePosition
        guard remainingFrames > 0 else {
            reachedEndOfStream = true
            status.pointee = .endOfStream
            return nil
        }

        let requestedFrames = max(
            1,
            min(
                AVAudioFrameCount(requestedPackets),
                inputBuffer.frameCapacity,
                AVAudioFrameCount(remainingFrames)
            )
        )

        do {
            inputBuffer.frameLength = 0
            try sourceFile.read(into: inputBuffer, frameCount: requestedFrames)

            guard inputBuffer.frameLength > 0 else {
                reachedEndOfStream = true
                status.pointee = .endOfStream
                return nil
            }

            status.pointee = .haveData
            return inputBuffer
        } catch {
            readError = error
            status.pointee = .noDataNow
            return nil
        }
    }
}
