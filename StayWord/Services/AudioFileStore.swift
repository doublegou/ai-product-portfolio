import AVFAudio
import Foundation

struct ImportedAudio: Sendable {
    let relativePath: String
    let title: String
    let duration: TimeInterval
    let waveform: [Double]
}

struct RecordedAudio: Sendable {
    let relativePath: String
    let duration: TimeInterval
    let waveform: [Double]
    let markers: [MarkerDraft]
}

struct MarkerDraft: Sendable {
    let timestamp: TimeInterval
}

protocol AudioImportServiceProtocol: Sendable {
    func importAudio(from sourceURL: URL) async throws -> ImportedAudio
}

struct AudioFileStore: Sendable {
    private let folderName = "Recordings"

    var recordingsDirectory: URL {
        get throws {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            let folder = base.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            return folder
        }
    }

    func newRecordingURL() throws -> URL {
        try recordingsDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }

    func newImportedAudioURL(for sourceURL: URL) throws -> URL {
        let sourceExtension = sourceURL.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !sourceExtension.isEmpty else {
            throw StayWordError.invalidAudioFile
        }

        return try recordingsDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceExtension)
    }

    func relativePath(for url: URL) -> String {
        "\(folderName)/\(url.lastPathComponent)"
    }

    func url(for relativePath: String) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent(relativePath)
    }

    func remove(relativePath: String) throws {
        let url = url(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

actor AudioImportService: AudioImportServiceProtocol {
    private let fileStore: AudioFileStore

    init(fileStore: AudioFileStore) {
        self.fileStore = fileStore
    }

    func importAudio(from sourceURL: URL) async throws -> ImportedAudio {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destination = try fileStore.newImportedAudioURL(for: sourceURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            let audioFile = try AVAudioFile(forReading: destination)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            guard duration.isFinite, duration > 0 else {
                throw StayWordError.invalidAudioFile
            }

            let waveform = try WaveformExtractor.extract(from: destination)
            return ImportedAudio(
                relativePath: fileStore.relativePath(for: destination),
                title: sourceURL.deletingPathExtension().lastPathComponent,
                duration: duration,
                waveform: waveform
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if error is StayWordError {
                throw error
            }
            throw StayWordError.invalidAudioFile
        }
    }
}

enum WaveformExtractor {
    static func extract(from url: URL, targetSampleCount: Int = 120) throws -> [Double] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 4_096
        ) else {
            return []
        }

        var rawSamples: [Double] = []
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard
                buffer.frameLength > 0,
                let channels = buffer.floatChannelData
            else {
                break
            }

            let count = Int(buffer.frameLength)
            var sum: Double = 0
            for index in 0..<count {
                let value = Double(channels[0][index])
                sum += value * value
            }
            rawSamples.append(min(1, sqrt(sum / Double(max(count, 1))) * 5))
        }

        guard rawSamples.count > targetSampleCount else {
            return rawSamples
        }

        let stride = Double(rawSamples.count) / Double(targetSampleCount)
        return (0..<targetSampleCount).map { index in
            let lower = Int(Double(index) * stride)
            let upper = min(rawSamples.count, Int(Double(index + 1) * stride))
            guard lower < upper else { return 0 }
            return rawSamples[lower..<upper].max() ?? 0
        }
    }
}
