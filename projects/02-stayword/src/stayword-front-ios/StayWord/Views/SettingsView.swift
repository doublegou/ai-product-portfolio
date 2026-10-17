import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL

    private let appStoreID = "6795797415"
    private let supportEmail = "doublegou@gmail.com"

    var body: some View {
        List {
            Section {
                NavigationLink {
                    TranscriptionLanguagePreferenceView()
                } label: {
                    HStack {
                        Label("Language Preference", systemImage: "waveform.badge.mic")
                        Spacer()
                        Text(services.transcriptionPreferences.preferredLanguage.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings-language-preference")
            } footer: {
                Text("The selected language is prioritized during transcription. Mixed-language speech is still supported.")
            }

            Section {
                Button {
                    openRatingPage()
                } label: {
                    Label("Rate StayWord", systemImage: "star")
                }
                .accessibilityIdentifier("settings-rate")

                Button {
                    openContactEmail()
                } label: {
                    Label("Contact Us", systemImage: "envelope")
                }
                .accessibilityIdentifier("settings-contact")
            }

            Section {
                LabeledContent {
                    Text(versionText)
                } label: {
                    Label("Version", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0.1"
        return "V\(version)"
    }

    private func openRatingPage() {
        guard let url = URL(
            string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review"
        ) else { return }
        openURL(url)
    }

    private func openContactEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: String(localized: "StayWord Feedback")
            ),
            URLQueryItem(
                name: "body",
                value: contactEmailBody
            ),
        ]
        guard let url = components.url else { return }
        openURL(url)
    }

    private var contactEmailBody: String {
        """
        \(String(localized: "Please describe your question or feedback here."))


        ---
        StayWord \(versionText)
        \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        \(UIDevice.current.model)
        """
    }
}

private struct TranscriptionLanguagePreferenceView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var preferences = services.transcriptionPreferences

        List {
            Section {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Button {
                        preferences.preferredLanguage = language
                    } label: {
                        HStack {
                            Text(language.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if preferences.preferredLanguage == language {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("transcription-language-\(language.rawValue)")
                }
            } footer: {
                Text("Choose the main language you usually record. The model can still recognize supported languages mixed into the same recording.")
            }
        }
        .navigationTitle("Language Preference")
        .navigationBarTitleDisplayMode(.large)
    }
}
