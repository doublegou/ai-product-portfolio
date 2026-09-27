import Foundation
import SwiftData

enum ProcessingState: String, Codable, CaseIterable {
    case ready
    case preparing
    case vad
    case transcribing
    case summarizing
    case completed
    case failed

    var localizedTitle: String {
        switch self {
        case .ready: String(localized: "Ready")
        case .preparing: String(localized: "Preparing")
        case .vad: String(localized: "Detecting Speech")
        case .transcribing: String(localized: "Transcribing")
        case .summarizing: String(localized: "Generating Summary")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Processing Failed")
        }
    }

    /// The recording still has work left before its final result is available.
    /// `ready` is included because it represents a queued recording that has
    /// not started its first processing stage yet.
    var isOverallProcessing: Bool {
        switch self {
        case .ready, .preparing, .vad, .transcribing, .summarizing:
            true
        case .completed, .failed:
            false
        }
    }

    /// The transcript itself is still being produced or finalized.
    /// Summary generation happens after this lifecycle has finished.
    var isTranscriptionProcessing: Bool {
        switch self {
        case .ready, .preparing, .vad, .transcribing:
            true
        case .summarizing, .completed, .failed:
            false
        }
    }
}

enum SummaryKind: String, Codable {
    case none
    case localLanguageModel
    case extractive

    var localizedTitle: String? {
        switch self {
        case .none:
            nil
        case .localLanguageModel:
            String(localized: "On-Device Summary")
        case .extractive:
            String(localized: "Basic Summary")
        }
    }
}

@Model
final class RecordingFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \AudioRecording.folder)
    var recordings: [AudioRecording] = []

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

@Model
final class AudioRecording {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var audioRelativePath: String
    var isFavorite: Bool
    var processingStateRaw: String
    var summaryKindRaw: String
    var summarySubject: String
    var summaryText: String
    var failureMessage: String?
    var summaryFailureMessage: String?
    var waveformData: Data?
    var deletedAt: Date?
    var transcriptionCheckpointSample: Int64 = 0
    var transcriptionCheckpointSourceSize: Int64 = 0
    var transcriptionCheckpointSourceModifiedAt: Date?
    var transcriptionCheckpointProfileVersion: Int = 0

    var folder: RecordingFolder?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.recording)
    var transcriptSegments: [TranscriptSegment] = []

    @Relationship(deleteRule: .cascade, inverse: \RecordingMarker.recording)
    var markers: [RecordingMarker] = []

    var processingState: ProcessingState {
        get { ProcessingState(rawValue: processingStateRaw) ?? .ready }
        set { processingStateRaw = newValue.rawValue }
    }

    var summaryKind: SummaryKind {
        get { SummaryKind(rawValue: summaryKindRaw) ?? .none }
        set { summaryKindRaw = newValue.rawValue }
    }

    var waveform: [Double] {
        get {
            guard let waveformData else { return [] }
            return (try? JSONDecoder().decode([Double].self, from: waveformData)) ?? []
        }
        set {
            waveformData = try? JSONEncoder().encode(newValue)
        }
    }

    var transcriptText: String {
        transcriptSegments
            .sorted { $0.startTime < $1.startTime }
            .map(\.text)
            .joined(separator: "\n")
    }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        audioRelativePath: String,
        isFavorite: Bool = false,
        processingState: ProcessingState = .ready,
        summaryKind: SummaryKind = .none,
        summarySubject: String = "",
        summaryText: String = "",
        failureMessage: String? = nil,
        summaryFailureMessage: String? = nil,
        waveform: [Double] = [],
        folder: RecordingFolder? = nil,
        deletedAt: Date? = nil,
        transcriptionCheckpointSample: Int64 = 0,
        transcriptionCheckpointSourceSize: Int64 = 0,
        transcriptionCheckpointSourceModifiedAt: Date? = nil,
        transcriptionCheckpointProfileVersion: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioRelativePath = audioRelativePath
        self.isFavorite = isFavorite
        self.processingStateRaw = processingState.rawValue
        self.summaryKindRaw = summaryKind.rawValue
        self.summarySubject = summarySubject
        self.summaryText = summaryText
        self.failureMessage = failureMessage
        self.summaryFailureMessage = summaryFailureMessage
        self.folder = folder
        self.deletedAt = deletedAt
        self.transcriptionCheckpointSample = transcriptionCheckpointSample
        self.transcriptionCheckpointSourceSize = transcriptionCheckpointSourceSize
        self.transcriptionCheckpointSourceModifiedAt =
            transcriptionCheckpointSourceModifiedAt
        self.transcriptionCheckpointProfileVersion =
            transcriptionCheckpointProfileVersion
        self.waveformData = try? JSONEncoder().encode(waveform)
    }
}

@Model
final class TranscriptSegment {
    @Attribute(.unique) var id: UUID
    var startTime: TimeInterval
    var duration: TimeInterval
    var text: String
    var sortOrder: Int
    var recording: AudioRecording?

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        duration: TimeInterval = 0,
        text: String,
        sortOrder: Int = 0,
        recording: AudioRecording? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.text = text
        self.sortOrder = sortOrder
        self.recording = recording
    }
}

@Model
final class RecordingMarker {
    @Attribute(.unique) var id: UUID
    var timestamp: TimeInterval
    var title: String
    var recording: AudioRecording?

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        title: String = "",
        recording: AudioRecording? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.recording = recording
    }
}
