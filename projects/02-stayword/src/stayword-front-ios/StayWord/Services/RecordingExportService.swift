import Foundation

enum RecordingExportKind: Sendable {
    case audio
    case transcript
    case summary
}

struct RecordingExportTranscriptSegment: Sendable, Equatable {
    let startTime: TimeInterval
    let text: String
}

struct RecordingExportSnapshot: Sendable {
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    let audioURL: URL
    let summarySubject: String
    let summaryText: String
    let transcriptSegments: [RecordingExportTranscriptSegment]
}

struct PreparedRecordingExport: Sendable, Identifiable {
    let id = UUID()
    let fileURL: URL
    let directoryURL: URL
}

enum RecordingExportError: LocalizedError {
    case audioNotFound
    case transcriptUnavailable
    case summaryUnavailable
    case preparationFailed

    var errorDescription: String? {
        switch self {
        case .audioNotFound:
            String(localized: "The recording file could not be found.")
        case .transcriptUnavailable:
            String(localized: "There is no transcript to share.")
        case .summaryUnavailable:
            String(localized: "There is no summary to share.")
        case .preparationFailed:
            String(localized: "The export file could not be prepared.")
        }
    }
}

struct RecordingExportService: Sendable {
    private static let staleExportAge: TimeInterval = 24 * 60 * 60

    private let fileStore: AudioFileStore
    private let exportRoot: URL

    init(
        fileStore: AudioFileStore,
        exportRoot: URL? = nil
    ) {
        self.fileStore = fileStore
        self.exportRoot = exportRoot
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("StayWordShare", isDirectory: true)
    }

    @MainActor
    func snapshot(for recording: AudioRecording) -> RecordingExportSnapshot {
        RecordingExportSnapshot(
            title: recording.title,
            createdAt: recording.createdAt,
            duration: recording.duration,
            audioURL: fileStore.url(for: recording.audioRelativePath),
            summarySubject: SummaryMarkupCleaner.clean(recording.summarySubject),
            summaryText: SummaryMarkupCleaner.clean(recording.summaryText),
            transcriptSegments: recording.transcriptSegments.map {
                RecordingExportTranscriptSegment(
                    startTime: $0.startTime,
                    text: $0.text
                )
            }
        )
    }

    func isAvailable(
        _ kind: RecordingExportKind,
        in snapshot: RecordingExportSnapshot
    ) -> Bool {
        switch kind {
        case .audio:
            FileManager.default.fileExists(atPath: snapshot.audioURL.path)
        case .transcript:
            snapshot.transcriptSegments.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .summary:
            !snapshot.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func prepare(
        _ kind: RecordingExportKind,
        from snapshot: RecordingExportSnapshot
    ) async throws -> PreparedRecordingExport {
        try await Task.detached(priority: .userInitiated) {
            try prepareSynchronously(kind, from: snapshot)
        }.value
    }

    func cleanup(_ export: PreparedRecordingExport) {
        try? FileManager.default.removeItem(at: export.directoryURL)
    }

    static func sanitizedFileName(
        _ title: String,
        fallback: String = "Recording"
    ) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters)
            .union(.newlines)
        let replacedScalars = title.unicodeScalars.map { scalar -> Character in
            invalidCharacters.contains(scalar) ? "-" : Character(scalar)
        }
        let normalized = String(replacedScalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        let limited = String(normalized.prefix(100))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        return limited.isEmpty ? fallback : limited
    }

    static func transcriptText(
        for snapshot: RecordingExportSnapshot,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> String {
        let segments = snapshot.transcriptSegments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startTime < $1.startTime }
        guard !segments.isEmpty else {
            throw RecordingExportError.transcriptUnavailable
        }

        let body = segments.map {
            "[\($0.startTime.audioTimestamp)] \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return documentHeader(
            for: snapshot,
            heading: String(localized: "Transcript", locale: locale),
            locale: locale,
            timeZone: timeZone
        ) + body.joined(separator: "\n") + "\n"
    }

    static func summaryText(
        for snapshot: RecordingExportSnapshot,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> String {
        let subject = SummaryMarkupCleaner.clean(snapshot.summarySubject)
        let summary = SummaryMarkupCleaner.clean(snapshot.summaryText)
        guard !summary.isEmpty else {
            throw RecordingExportError.summaryUnavailable
        }

        let body = [subject, summary]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return documentHeader(
            for: snapshot,
            heading: String(localized: "Summary", locale: locale),
            locale: locale,
            timeZone: timeZone
        ) + body + "\n"
    }

    private func prepareSynchronously(
        _ kind: RecordingExportKind,
        from snapshot: RecordingExportSnapshot
    ) throws -> PreparedRecordingExport {
        let fileManager = FileManager.default
        cleanupStaleExports(using: fileManager)

        let directory = exportRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
                ]
            )

            let baseName = Self.sanitizedFileName(
                snapshot.title,
                fallback: String(localized: "Recording")
            )
            let fileURL: URL
            switch kind {
            case .audio:
                guard fileManager.fileExists(atPath: snapshot.audioURL.path) else {
                    throw RecordingExportError.audioNotFound
                }
                let fileName = snapshot.audioURL.pathExtension.isEmpty
                    ? baseName
                    : "\(baseName).\(snapshot.audioURL.pathExtension)"
                fileURL = directory.appendingPathComponent(fileName)
                do {
                    try fileManager.linkItem(at: snapshot.audioURL, to: fileURL)
                } catch {
                    try fileManager.copyItem(at: snapshot.audioURL, to: fileURL)
                }
            case .transcript:
                fileURL = directory
                    .appendingPathComponent("\(baseName) - \(String(localized: "Transcript"))")
                    .appendingPathExtension("txt")
                let text = try Self.transcriptText(for: snapshot)
                try Data(text.utf8).write(to: fileURL, options: .atomic)
            case .summary:
                fileURL = directory
                    .appendingPathComponent("\(baseName) - \(String(localized: "Summary"))")
                    .appendingPathExtension("txt")
                let text = try Self.summaryText(for: snapshot)
                try Data(text.utf8).write(to: fileURL, options: .atomic)
            }

            return PreparedRecordingExport(
                fileURL: fileURL,
                directoryURL: directory
            )
        } catch let error as RecordingExportError {
            try? fileManager.removeItem(at: directory)
            throw error
        } catch {
            try? fileManager.removeItem(at: directory)
            throw RecordingExportError.preparationFailed
        }
    }

    private func cleanupStaleExports(using fileManager: FileManager) {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: exportRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Self.staleExportAge)
        for directory in directories {
            let values = try? directory.resourceValues(
                forKeys: [.contentModificationDateKey]
            )
            if let modifiedAt = values?.contentModificationDate,
               modifiedAt < cutoff {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private static func documentHeader(
        for snapshot: RecordingExportSnapshot,
        heading: String,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        var dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
        dateStyle.locale = locale
        dateStyle.timeZone = timeZone
        let date = snapshot.createdAt.formatted(dateStyle)
        let duration = String(
            format: String(localized: "Duration: %@", locale: locale),
            snapshot.duration.audioTimestamp
        )
        return "\(snapshot.title)\n\(date)\n\(duration)\n\n\(heading)\n\n"
    }
}
