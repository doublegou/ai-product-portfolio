import SwiftData
import SwiftUI

struct RecordingEditView: View {
    let recording: AudioRecording

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String
    @State private var subject: String
    @State private var summary: String
    @State private var confirmsDiscard = false

    init(recording: AudioRecording) {
        self.recording = recording
        _title = State(initialValue: recording.title)
        _subject = State(initialValue: recording.summarySubject)
        _summary = State(initialValue: recording.summaryText)
    }

    private var hasChanges: Bool {
        title != recording.title
            || subject != recording.summarySubject
            || summary != recording.summaryText
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Summary") {
                    TextField("Subject", text: $subject)
                    TextEditor(text: $summary)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Summary text")
                }
            }
            .navigationTitle("Edit Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if hasChanges {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            "Discard changes?",
            isPresented: $confirmsDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private func save() {
        recording.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        recording.summarySubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        recording.summaryText = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        if services.save(modelContext) {
            dismiss()
        }
    }
}
