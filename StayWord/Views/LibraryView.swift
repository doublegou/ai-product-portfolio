import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecordingFolder.sortOrder)
    private var folders: [RecordingFolder]
    @Query private var recordings: [AudioRecording]

    @State private var showsNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderToRename: RecordingFolder?
    @State private var renamedFolderName = ""
    @State private var foldersToDelete: [RecordingFolder] = []
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.recordings(.all)) {
                    Label("All Recordings", systemImage: "waveform")
                        .badge(activeRecordings.count)
                }

                NavigationLink(value: AppRoute.recordings(.favorites)) {
                    Label("Favorites", systemImage: "heart")
                        .badge(activeRecordings.lazy.filter(\.isFavorite).count)
                }

                NavigationLink(value: AppRoute.recentlyDeleted) {
                    Label("Recently Deleted", systemImage: "trash")
                        .badge(recentlyDeletedRecordings.count)
                }
            }

            Section("My Folders") {
                ForEach(folders) { folder in
                    Group {
                        if editMode == .active {
                            HStack {
                                Label(folder.name, systemImage: "folder")

                                Spacer()

                                folderActionsMenu(for: folder)
                            }
                        } else {
                            NavigationLink(value: AppRoute.recordings(.folder(folder.id))) {
                                Label(folder.name, systemImage: "folder")
                                    .badge(folder.recordings.lazy.filter { $0.deletedAt == nil }.count)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            foldersToDelete = [folder]
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            folderToRename = folder
                            renamedFolderName = folder.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            folderToRename = folder
                            renamedFolderName = folder.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            foldersToDelete = [folder]
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: moveFolders)
                .onDelete(perform: deleteFolders)
            }
        }
        .navigationTitle("Voice Recordings")
        .navigationBarTitleDisplayMode(.large)
        .environment(\.editMode, $editMode)
        .toolbar {
            if editMode == .active {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newFolderName = ""
                        showsNewFolderAlert = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            editMode = .inactive
                        }
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newFolderName = ""
                        showsNewFolderAlert = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        withAnimation {
                            editMode = .active
                        }
                    }
                }
            }

        }
        .safeAreaInset(edge: .bottom) {
            if editMode != .active,
               !router.presentsRecorder,
               !showsNewFolderAlert,
               folderToRename == nil {
                NativeRecordButton {
                    router.startRecording()
                }
            }
        }
        .task {
            // Present the library before resuming work that may initialize
            // transcription or summary models.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            services.processor.restoreInterruptedJobs(
                from: activeRecordings.filter {
                    $0.processingState.isOverallProcessing
                },
                in: modelContext
            )
        }
        .alert("New Folder", isPresented: $showsNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                createFolder()
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for this folder.")
        }
        .alert(
            "Rename Folder",
            isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )
        ) {
            TextField("Name", text: $renamedFolderName)
            Button("Cancel", role: .cancel) {
                folderToRename = nil
            }
            Button("Save") {
                renameFolder()
            }
            .disabled(renamedFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            deleteAlertTitle,
            isPresented: Binding(
                get: { !foldersToDelete.isEmpty },
                set: { if !$0 { foldersToDelete.removeAll() } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                foldersToDelete.removeAll()
            }
            Button("Delete", role: .destructive) {
                deletePendingFolders()
            }
        } message: {
            Text(deleteAlertMessage)
        }
    }

    private func folderActionsMenu(for folder: RecordingFolder) -> some View {
        Menu {
            Button {
                folderToRename = folder
                renamedFolderName = folder.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                foldersToDelete = [folder]
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .labelStyle(.iconOnly)
        .accessibilityHint("Shows actions for this folder")
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !name.isEmpty,
            !folders.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }

        modelContext.insert(RecordingFolder(name: name, sortOrder: folders.count))
        services.save(modelContext)
    }

    private func renameFolder() {
        guard let folderToRename else { return }
        let name = renamedFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        folderToRename.name = name
        if services.save(modelContext) {
            self.folderToRename = nil
        }
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        var reordered = folders
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in reordered.enumerated() {
            folder.sortOrder = index
        }
        services.save(modelContext)
    }

    private func deleteFolders(at offsets: IndexSet) {
        foldersToDelete = offsets.map { folders[$0] }
    }

    private func normalizeFolderOrder() {
        for (index, folder) in folders.enumerated() {
            folder.sortOrder = index
        }
        services.save(modelContext)
    }

    private var deleteAlertTitle: String {
        foldersToDelete.count > 1
            ? String(localized: "Delete Folders & Recordings?")
            : String(localized: "Delete Folder & Recordings?")
    }

    private var deleteAlertMessage: String {
        let recordingCount = foldersToDelete.reduce(0) {
            $0 + $1.recordings.lazy.filter { $0.deletedAt == nil }.count
        }
        if foldersToDelete.count > 1 {
            return String(
                localized: "\(foldersToDelete.count) folders will be deleted and \(recordingCount) recordings will move to Recently Deleted."
            )
        }
        return String(
            localized: "\(recordingCount) recordings in this folder will move to Recently Deleted."
        )
    }

    private func deletePendingFolders() {
        let deletedIDs = Set(foldersToDelete.map(\.id))

        for folder in foldersToDelete {
            for recording in folder.recordings {
                if recording.deletedAt == nil {
                    recording.deletedAt = .now
                }
                recording.folder = nil
            }
            modelContext.delete(folder)
        }

        for (index, folder) in folders
            .filter({ !deletedIDs.contains($0.id) })
            .enumerated() {
            folder.sortOrder = index
        }

        if services.save(modelContext) {
            foldersToDelete.removeAll()
        }
    }

    private var activeRecordings: [AudioRecording] {
        recordings.filter { $0.deletedAt == nil }
    }

    private var recentlyDeletedRecordings: [AudioRecording] {
        recordings.filter { $0.deletedAt != nil }
    }
}
