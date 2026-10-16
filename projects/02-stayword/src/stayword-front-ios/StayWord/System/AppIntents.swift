import AppIntents
import Foundation

enum AppIntentKeys {
    static let startRecording = "intent.startRecording"
    static let openRecent = "intent.openRecent"
}

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Opens StayWord and starts a new voice recording.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: AppIntentKeys.startRecording)
        return .result()
    }
}

struct OpenRecentRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Recent Recording"
    static let description = IntentDescription("Opens the most recent recording in StayWord.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: AppIntentKeys.openRecent)
        return .result()
    }
}

struct StayWordShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start a recording in \(.applicationName)",
                "Record with \(.applicationName)",
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle"
        )

        AppShortcut(
            intent: OpenRecentRecordingIntent(),
            phrases: [
                "Open my recent recording in \(.applicationName)",
            ],
            shortTitle: "Recent Recording",
            systemImageName: "waveform"
        )
    }
}
