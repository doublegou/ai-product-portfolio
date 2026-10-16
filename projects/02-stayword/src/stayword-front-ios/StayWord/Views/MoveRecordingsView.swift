import SwiftData
import SwiftUI

struct MoveRecordingsView: View {
    let recordings: [AudioRecording]
    let onComplete: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecordingFolder.sortOrder)
    private var folders: [RecordingFolder]

    var body: some View {
        NavigationStack {
            List {
                Button {
                    move(to: nil)
                } label: {
                    Label("No Folder", systemImage: "tray")
                }

                ForEach(folders) { folder in
                    Button {
                        move(to: folder)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                }
            }
            .navigationTitle("Select a Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        AdaptiveToolbarButtonIcon(
                            "Close",
                            systemImage: "xmark"
                        )
                    }
                    .adaptiveToolbarCircleButtonStyle()
                    .accessibilityIdentifier("move-recordings-close")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func move(to folder: RecordingFolder?) {
        for recording in recordings {
            recording.folder = folder
        }
        if services.save(modelContext) {
            onComplete()
            dismiss()
        }
    }
}
