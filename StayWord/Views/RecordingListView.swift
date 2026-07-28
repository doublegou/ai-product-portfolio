import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct RecordingListView: View {
    let filter: RecordingListFilter

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioRecording.createdAt, order: .reverse)
    private var recordings: [AudioRecording]
    @Query(sort: \RecordingFolder.sortOrder)
    private var folders: [RecordingFolder]

    @State private var searchText = ""
    @State private var searchIsPresented = false
    @State private var searchIsInstalled = false
    @State private var selectedIDs = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var confirmsDelete = false
    @State private var showsMoveSheet = false
    @State private var recordingToRename: AudioRecording?
    @State private var renamedRecordingTitle = ""

    private var title: String {
        switch filter {
        case .all:
            String(localized: "All Recordings")
        case .favorites:
            String(localized: "Favorites")
        case .folder(let id):
            folders.first(where: { $0.id == id })?.name ?? String(localized: "Folder")
        }
    }

    private var visibleRecordings: [AudioRecording] {
        recordings.filter { recording in
            guard recording.deletedAt == nil else { return false }

            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .favorites:
                matchesFilter = recording.isFavorite
            case .folder(let id):
                matchesFilter = recording.folder?.id == id
            }

            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let searchable = [
                recording.title,
                recording.summarySubject,
                recording.summaryText,
                recording.transcriptText,
            ].joined(separator: "\n")
            return searchable.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        List(selection: $selectedIDs) {
            ForEach(visibleRecordings) { recording in
                Group {
                    if editMode == .active {
                        RecordingRow(recording: recording)
                    } else {
                        Button {
                            router.open(recording.id)
                        } label: {
                            RecordingRow(recording: recording)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tag(recording.id)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        selectedIDs = [recording.id]
                        confirmsDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }

                    Button {
                        selectedIDs = [recording.id]
                        showsMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.indigo)

                    Button {
                        recording.isFavorite.toggle()
                        services.save(modelContext)
                    } label: {
                        Label(
                            recording.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: recording.isFavorite ? "heart.slash" : "heart"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .tint(.pink)

                    Button {
                        beginRenaming(recording)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        beginRenaming(recording)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        recording.isFavorite.toggle()
                        services.save(modelContext)
                    } label: {
                        Label(
                            recording.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: recording.isFavorite ? "heart.slash" : "heart"
                        )
                    }

                    Button {
                        selectedIDs = [recording.id]
                        showsMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "folder")
                    }

                    Button(role: .destructive) {
                        selectedIDs = [recording.id]
                        confirmsDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if visibleRecordings.isEmpty {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty ? "No Recordings" : "No Results",
                        systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass"
                    )
                } description: {
                    Text(
                        searchText.isEmpty
                            ? "Record or import audio to get started."
                            : "Try a different title or transcript search."
                    )
                } actions: {
                    if searchText.isEmpty {
                        Button("Import Audio") {
                            showsImporter = true
                        }
                        .nativeProminentButtonStyle()
                    }
                }
            } else if isImporting {
                ProgressView("Importing Audio")
                    .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .modifier(
            RecordingSearchModifier(
                text: $searchText,
                isPresented: $searchIsPresented,
                isInstalled: searchIsInstalled
            )
        )
        .onChange(of: searchIsPresented) { wasPresented, isPresented in
            if wasPresented, !isPresented {
                searchText = ""
                searchIsInstalled = false
            }
        }
        .task(id: searchIsInstalled) {
            guard searchIsInstalled, !searchIsPresented else { return }

            // Let the navigation bar finish installing the search drawer before
            // asking it to become first responder. Presenting it in the same
            // update can make iOS place it in the bottom toolbar on first use.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 120_000_000)

            guard !Task.isCancelled, searchIsInstalled else { return }
            searchIsPresented = true
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            if editMode == .active {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editMode = .inactive
                        selectedIDs.removeAll()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation {
                                editMode = .active
                            }
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }

                        Button {
                            showsImporter = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .labelStyle(.iconOnly)
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                if editMode == .active {
                    Button {
                        showsMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .disabled(selectedIDs.isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode != .active,
               !router.presentsRecorder,
               !searchIsPresented,
               recordingToRename == nil {
                NativeRecordButton {
                    router.startRecording()
                }
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert(
            "Unable to Import Audio",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert(
            "Delete selected recordings?",
            isPresented: $confirmsDelete
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("The selected recordings will move to Recently Deleted.")
        }
        .alert(
            "Rename Recording",
            isPresented: Binding(
                get: { recordingToRename != nil },
                set: { if !$0 { recordingToRename = nil } }
            )
        ) {
            TextField("Name", text: $renamedRecordingTitle)
            Button("Cancel", role: .cancel) {
                recordingToRename = nil
            }
            Button("Save") {
                renameRecording()
            }
            .disabled(
                renamedRecordingTitle
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
        } message: {
            Text("Enter a new name for this recording.")
        }
        .sheet(isPresented: $showsMoveSheet) {
            MoveRecordingsView(
                recordings: recordings.filter { selectedIDs.contains($0.id) }
            ) {
                selectedIDs.removeAll()
                editMode = .inactive
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
            return
        }

        isImporting = true
        Task {
            do {
                let imported = try await services.importer.importAudio(from: url)
                let recording = AudioRecording(
                    title: imported.title,
                    duration: imported.duration,
                    audioRelativePath: imported.relativePath,
                    processingState: .ready,
                    waveform: imported.waveform,
                    folder: folderForCurrentFilter
                )
                modelContext.insert(recording)
                guard services.save(modelContext) else {
                    try? AudioFileStore().remove(relativePath: imported.relativePath)
                    isImporting = false
                    return
                }
                isImporting = false
                router.open(recording.id)
                services.processor.enqueue(recording, in: modelContext)
            } catch {
                isImporting = false
                importError = error.localizedDescription
            }
        }
    }

    private var folderForCurrentFilter: RecordingFolder? {
        guard case .folder(let id) = filter else { return nil }
        return folders.first { $0.id == id }
    }

    private func deleteSelected() {
        for recording in recordings where selectedIDs.contains(recording.id) {
            recording.deletedAt = .now
        }
        if services.save(modelContext) {
            selectedIDs.removeAll()
            editMode = .inactive
        }
    }

    private func renameRecording() {
        guard let recordingToRename else { return }

        recordingToRename.title = renamedRecordingTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if services.save(modelContext) {
            self.recordingToRename = nil
        }
    }

    private func beginRenaming(_ recording: AudioRecording) {
        renamedRecordingTitle = recording.title
        recordingToRename = recording
    }

    private func presentSearch() {
        guard !searchIsInstalled else {
            searchIsPresented = true
            return
        }

        searchIsInstalled = true
    }
}

struct RecentlyDeletedView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query private var recordings: [AudioRecording]

    @State private var selectedIDs = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var permanentDeleteIDs = Set<UUID>()
    @State private var permanentDeletionIsAll = false
    @State private var confirmsPermanentDeletion = false
    @State private var recordingActionID: UUID?

    private var deletedRecordings: [AudioRecording] {
        recordings
            .filter { $0.deletedAt != nil }
            .sorted {
                ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
            }
    }

    var body: some View {
        List(selection: $selectedIDs) {
            ForEach(deletedRecordings) { recording in
                Group {
                    if editMode == .active {
                        RecordingRow(recording: recording)
                    } else {
                        Button {
                            recordingActionID = recording.id
                        } label: {
                            RecordingRow(recording: recording)
                        }
                        .buttonStyle(.plain)
                    }
                }
                    .tag(recording.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            requestPermanentDeletion(of: [recording.id])
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }

                        Button {
                            recover([recording.id])
                        } label: {
                            Label("Recover", systemImage: "arrow.up.bin")
                                .labelStyle(.iconOnly)
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            requestPermanentDeletion(of: [recording.id])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            recover([recording.id])
                        } label: {
                            Label("Recover", systemImage: "arrow.up.bin")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .overlay {
            if deletedRecordings.isEmpty {
                ContentUnavailableView(
                    "No Recently Deleted Recordings",
                    systemImage: "trash",
                    description: Text("Deleted recordings will appear here.")
                )
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if editMode == .active {
                ToolbarItem(placement: .topBarTrailing) {
                    selectionActionsMenu
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        leaveSelectionMode()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") {
                        withAnimation {
                            editMode = .active
                        }
                    }
                    .disabled(deletedRecordings.isEmpty)
                }
            }
        }
        .alert(
            permanentDeleteAlertTitle,
            isPresented: $confirmsPermanentDeletion
        ) {
            Button("Cancel", role: .cancel) {
                permanentDeleteIDs.removeAll()
                permanentDeletionIsAll = false
            }
            Button("Delete", role: .destructive) {
                permanentlyDeleteRecordings(with: permanentDeleteIDs)
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Recover or Delete Recording?",
            isPresented: Binding(
                get: { recordingActionID != nil },
                set: { if !$0 { recordingActionID = nil } }
            ),
            presenting: recordingForActions
        ) { recording in
            Button("Recover") {
                recordingActionID = nil
                recover([recording.id])
            }

            Button("Delete", role: .destructive) {
                recordingActionID = nil
                Task { @MainActor in
                    await Task.yield()
                    requestPermanentDeletion(of: [recording.id])
                }
            }
        } message: { recording in
            Text(recording.title)
        }
    }

    private var recordingForActions: AudioRecording? {
        deletedRecordings.first { $0.id == recordingActionID }
    }

    private var selectionActionsMenu: some View {
        Menu {
            if selectedIDs.isEmpty {
                Button(role: .destructive) {
                    requestPermanentDeletion(
                        of: Set(deletedRecordings.map(\.id)),
                        isAll: true
                    )
                } label: {
                    Label("Delete All", systemImage: "trash")
                }

                Button {
                    recover(Set(deletedRecordings.map(\.id)))
                } label: {
                    Label("Recover All", systemImage: "arrow.up.bin")
                }
            } else {
                Button(role: .destructive) {
                    requestPermanentDeletion(of: selectedIDs)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    recover(selectedIDs)
                } label: {
                    Label("Recover", systemImage: "arrow.up.bin")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .labelStyle(.iconOnly)
    }

    private var permanentDeleteAlertTitle: String {
        if permanentDeletionIsAll {
            return String(localized: "Delete All Recordings Permanently?")
        }
        if permanentDeleteIDs.count == 1 {
            return String(localized: "Delete Recording Permanently?")
        }
        return String(localized: "Delete Selected Recordings Permanently?")
    }

    private func requestPermanentDeletion(
        of ids: Set<UUID>,
        isAll: Bool = false
    ) {
        guard !ids.isEmpty else { return }
        permanentDeleteIDs = ids
        permanentDeletionIsAll = isAll
        confirmsPermanentDeletion = true
    }

    private func recover(_ ids: Set<UUID>) {
        let remainingCount = deletedRecordings.lazy
            .filter { !ids.contains($0.id) }
            .count

        for recording in recordings where ids.contains(recording.id) {
            recording.deletedAt = nil
        }
        guard services.save(modelContext) else { return }
        selectedIDs.subtract(ids)

        if remainingCount == 0 {
            leaveSelectionMode()
        }
    }

    private func permanentlyDeleteRecordings(with ids: Set<UUID>) {
        let remainingCount = deletedRecordings.lazy
            .filter { !ids.contains($0.id) }
            .count

        let recordingsToDelete = recordings.filter { ids.contains($0.id) }
        let audioPaths = recordingsToDelete.map(\.audioRelativePath)

        for recording in recordingsToDelete {
            modelContext.delete(recording)
        }
        guard services.save(modelContext) else { return }

        for audioPath in audioPaths {
            do {
                try AudioFileStore().remove(relativePath: audioPath)
            } catch {
                services.report(error)
            }
        }
        permanentDeleteIDs.removeAll()
        permanentDeletionIsAll = false
        selectedIDs.subtract(ids)

        if remainingCount == 0 {
            leaveSelectionMode()
        }
    }

    private func leaveSelectionMode() {
        withAnimation {
            selectedIDs.removeAll()
            editMode = .inactive
        }
    }
}

private struct RecordingSearchModifier: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let isInstalled: Bool

    func body(content: Content) -> some View {
        if isInstalled {
            content.searchable(
                text: $text,
                isPresented: $isPresented,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Title or transcript"
            )
        } else {
            content
        }
    }
}
