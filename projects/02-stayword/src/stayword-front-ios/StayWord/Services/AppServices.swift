import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppServices {
    let recorder: AudioRecorderController
    let player: AudioPlayerController
    let importer: AudioImportService
    let exporter: RecordingExportService
    let transcriptionPreferences: TranscriptionPreferences
    let reviewPrompts: ReviewPromptController
    let processor: ProcessingCoordinator
    let recordingTitleProvider: RecordingTitleProvider
    var operationErrorMessage: String?

    init() {
        let fileStore = AudioFileStore()
        self.recorder = AudioRecorderController(fileStore: fileStore)
        self.player = AudioPlayerController(fileStore: fileStore)
        self.importer = AudioImportService(fileStore: fileStore)
        self.exporter = RecordingExportService(fileStore: fileStore)
        let transcriptionPreferences = TranscriptionPreferences()
        let reviewPrompts = ReviewPromptController()
        self.transcriptionPreferences = transcriptionPreferences
        self.reviewPrompts = reviewPrompts
        #if DEBUG
        let summaryGenerationEnabled =
            ProcessInfo.processInfo.environment["STAYWORD_UI_TEST_DISABLE_SUMMARY"] != "1"
        #else
        let summaryGenerationEnabled = true
        #endif
        self.processor = ProcessingCoordinator(
            fileStore: fileStore,
            summaryGenerationEnabled: summaryGenerationEnabled,
            transcriptionLanguage: {
                transcriptionPreferences.preferredLanguage
            },
            reviewPrompts: reviewPrompts
        )
        self.recordingTitleProvider = RecordingTitleProvider()
    }

    @discardableResult
    func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            report(error)
            return false
        }
    }

    func report(_ error: Error) {
        operationErrorMessage = error.localizedDescription
    }
}

struct RecordingTitleProvider {
    func suggestedTitle(
        for date: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
