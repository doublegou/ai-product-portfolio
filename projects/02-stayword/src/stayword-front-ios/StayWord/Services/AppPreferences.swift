import Foundation
import Observation

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case mandarinChinese = "zh"
    case cantonese = "yue"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mandarinChinese:
            String(localized: "Chinese (Mandarin)")
        case .cantonese:
            String(localized: "Cantonese")
        case .english:
            String(localized: "English")
        case .japanese:
            String(localized: "Japanese")
        case .korean:
            String(localized: "Korean")
        }
    }
}

@MainActor
@Observable
final class TranscriptionPreferences {
    private enum Keys {
        static let preferredLanguage = "transcription.preferredLanguage"
    }

    private let defaults: UserDefaults

    var preferredLanguage: TranscriptionLanguage {
        didSet {
            defaults.set(preferredLanguage.rawValue, forKey: Keys.preferredLanguage)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredLanguage = TranscriptionLanguage(
            rawValue: defaults.string(forKey: Keys.preferredLanguage) ?? ""
        ) ?? .mandarinChinese
    }
}

@MainActor
@Observable
final class ReviewPromptController {
    private enum Keys {
        static let firstUseDate = "reviews.firstUseDate"
        static let successfulRecordingIDs = "reviews.successfulRecordingIDs"
        static let lastRequestedVersion = "reviews.lastRequestedVersion"
    }

    static let requiredSuccessfulTranscriptions = 3
    static let requiredUseDuration: TimeInterval = 3 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let appVersion: String
    private var successfulRecordingIDs: Set<String>
    private var isRequestPending = false

    private(set) var requestToken = 0

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        now: Date = .now
    ) {
        self.defaults = defaults
        appVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0.1"
        successfulRecordingIDs = Set(
            defaults.stringArray(forKey: Keys.successfulRecordingIDs) ?? []
        )

        if defaults.object(forKey: Keys.firstUseDate) == nil {
            defaults.set(now, forKey: Keys.firstUseDate)
        }
    }

    func recordSuccessfulTranscription(
        recordingID: UUID,
        now: Date = .now
    ) {
        let id = recordingID.uuidString
        guard successfulRecordingIDs.insert(id).inserted else { return }
        defaults.set(
            Array(successfulRecordingIDs).sorted(),
            forKey: Keys.successfulRecordingIDs
        )

        requestAutomaticPromptIfEligible(now: now)
    }

    func requestAutomaticPromptIfEligible(now: Date = .now) {
        guard !isRequestPending,
              successfulRecordingIDs.count >= Self.requiredSuccessfulTranscriptions,
              let firstUseDate = defaults.object(forKey: Keys.firstUseDate) as? Date,
              now.timeIntervalSince(firstUseDate) >= Self.requiredUseDuration,
              defaults.string(forKey: Keys.lastRequestedVersion) != appVersion
        else {
            return
        }

        isRequestPending = true
        requestToken += 1
    }

    func markAutomaticPromptRequested() {
        isRequestPending = false
        defaults.set(appVersion, forKey: Keys.lastRequestedVersion)
    }
}
