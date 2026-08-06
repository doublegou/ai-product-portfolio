import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordingListView: View {
    let filter: RecordingListFilter

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioRecording.createdAt, order: .reverse)
    private var recordings: [AudioRecording]
    @Query(sort: \RecordingFolder.sortOrder)
    private var folders: [RecordingFolder]

    @State private var searchText = ""
    @State private var searchIsPresented = false
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
                        .accessibilityIdentifier("recording-row-\(recording.id.uuidString)")
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
        .legacyNavigationBackButtonHidden()
        .background {
            RecordingSearchController(
                text: $searchText,
                isPresented: $searchIsPresented,
                prompt: String(localized: "Title or transcript")
            )
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            if #unavailable(iOS 26.0) {
                ToolbarItem(placement: .topBarLeading) {
                    LegacyNavigationBackButton {
                        dismiss()
                    }
                    .accessibilityIdentifier("recording-list-back")
                }
            }

            if editMode == .active {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editMode = .inactive
                        selectedIDs.removeAll()
                    } label: {
                        AdaptiveToolbarButtonIcon(
                            "Done",
                            systemImage: "checkmark"
                        )
                    }
                    .adaptiveToolbarCircleButtonStyle()
                    .accessibilityIdentifier("recording-list-done")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentSearch()
                    } label: {
                        AdaptiveToolbarButtonIcon(
                            "Search",
                            systemImage: "magnifyingglass"
                        )
                    }
                    .adaptiveToolbarCircleButtonStyle()
                    .accessibilityIdentifier("recording-list-search")
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    AdaptiveOverflowMenu(actions: [
                        AdaptiveMenuAction(
                            "Select",
                            systemImage: "checkmark.circle",
                            accessibilityIdentifier: "recording-list-select-action"
                        ) {
                            withAnimation {
                                editMode = .active
                            }
                        },
                        AdaptiveMenuAction(
                            "Import",
                            systemImage: "square.and.arrow.up",
                            accessibilityIdentifier: "recording-list-import-action"
                        ) {
                            showsImporter = true
                        }
                    ]) {
                        AdaptiveToolbarMenuIcon(
                            "More",
                            systemImage: "ellipsis"
                        )
                    }
                    .accessibilityIdentifier("recording-list-more")
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                if editMode == .active {
                    Button {
                        showsMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "folder")
                            .legacyFrostedToolbarCapsuleLabel()
                    }
                    .disabled(selectedIDs.isEmpty)

                    Spacer()

                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .legacyFrostedToolbarCapsuleLabel()
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
        searchIsPresented = true
    }
}

struct RecentlyDeletedView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
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
                        .accessibilityIdentifier("deleted-recording-row-\(recording.id.uuidString)")
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
        .legacyNavigationBackButtonHidden()
        .toolbar {
            if #unavailable(iOS 26.0) {
                ToolbarItem(placement: .topBarLeading) {
                    LegacyNavigationBackButton {
                        dismiss()
                    }
                    .accessibilityIdentifier("recently-deleted-back")
                }
            }

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
                        AdaptiveToolbarButtonIcon(
                            "Close",
                            systemImage: "xmark"
                        )
                    }
                    .adaptiveToolbarCircleButtonStyle()
                    .accessibilityIdentifier("recently-deleted-close")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            editMode = .active
                        }
                    } label: {
                        Text("Select")
                            .legacyFrostedToolbarCapsuleLabel()
                    }
                    .disabled(deletedRecordings.isEmpty)
                    .accessibilityIdentifier("recently-deleted-select")
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
            .accessibilityIdentifier("recently-deleted-confirm-permanent-delete")
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
            .accessibilityIdentifier("recently-deleted-item-delete")
        } message: { recording in
            Text(recording.title)
        }
    }

    private var recordingForActions: AudioRecording? {
        deletedRecordings.first { $0.id == recordingActionID }
    }

    private var selectionActionsMenu: some View {
        AdaptiveOverflowMenu(actions: selectionMenuActions) {
            AdaptiveToolbarMenuIcon(
                "More",
                systemImage: "ellipsis"
            )
        }
        .accessibilityIdentifier("recently-deleted-more")
    }

    private var selectionMenuActions: [AdaptiveMenuAction] {
        if selectedIDs.isEmpty {
            [
                AdaptiveMenuAction(
                    "Delete All",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    requestPermanentDeletion(
                        of: Set(deletedRecordings.map(\.id)),
                        isAll: true
                    )
                },
                AdaptiveMenuAction(
                    "Recover All",
                    systemImage: "arrow.up.bin"
                ) {
                    recover(Set(deletedRecordings.map(\.id)))
                }
            ]
        } else {
            [
                AdaptiveMenuAction(
                    "Delete",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    requestPermanentDeletion(of: selectedIDs)
                },
                AdaptiveMenuAction(
                    "Recover",
                    systemImage: "arrow.up.bin"
                ) {
                    recover(selectedIDs)
                }
            ]
        }
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

private struct RecordingSearchController: UIViewControllerRepresentable {
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(
            text: $text,
            isPresented: $isPresented,
            prompt: prompt
        )
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.tearDown()
    }

    @MainActor
    final class Controller: UIViewController,
        UISearchResultsUpdating,
        UISearchControllerDelegate,
        UISearchBarDelegate
    {
        private let searchController = UISearchController(searchResultsController: nil)
        private var text: Binding<String>?
        private var isPresented: Binding<Bool>?
        private weak var installedNavigationItem: UINavigationItem?
        private var previousSearchController: UISearchController?
        private var previousHidesSearchBarWhenScrolling = true
        private var previousSearchBarPlacement: UINavigationItem.SearchBarPlacement = .automatic
        private var previousAllowsToolbarIntegration = true
        private var presentationTask: Task<Void, Never>?

        override func loadView() {
            let view = UIView(frame: .zero)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            synchronizePresentation()
        }

        func update(
            text: Binding<String>,
            isPresented: Binding<Bool>,
            prompt: String
        ) {
            self.text = text
            self.isPresented = isPresented

            searchController.searchResultsUpdater = self
            searchController.delegate = self
            searchController.searchBar.delegate = self
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.searchBar.placeholder = prompt
            if #unavailable(iOS 26.0) {
                configureLegacySearchBar()
            }
            if searchController.searchBar.text != text.wrappedValue {
                searchController.searchBar.text = text.wrappedValue
            }

            synchronizePresentation()
        }

        func updateSearchResults(for searchController: UISearchController) {
            let updatedText = searchController.searchBar.text ?? ""
            if text?.wrappedValue != updatedText {
                text?.wrappedValue = updatedText
            }
        }

        func didDismissSearchController(_ searchController: UISearchController) {
            text?.wrappedValue = ""
            isPresented?.wrappedValue = false
            detach()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            closeSearch()
        }

        @objc private func closeSearch() {
            searchController.searchBar.text = ""
            text?.wrappedValue = ""
            isPresented?.wrappedValue = false
            searchController.searchBar.resignFirstResponder()
            searchController.isActive = false
        }

        func tearDown() {
            if searchController.isActive {
                searchController.isActive = false
            }
            detach()
        }

        func detach() {
            presentationTask?.cancel()
            presentationTask = nil
            guard let navigationItem = installedNavigationItem else { return }
            if navigationItem.searchController === searchController {
                navigationItem.searchController = previousSearchController
                navigationItem.hidesSearchBarWhenScrolling = previousHidesSearchBarWhenScrolling
                navigationItem.preferredSearchBarPlacement = previousSearchBarPlacement
                if #available(iOS 26.0, *) {
                    navigationItem.searchBarPlacementAllowsToolbarIntegration =
                        previousAllowsToolbarIntegration
                }
            }
            installedNavigationItem = nil
            previousSearchController = nil
        }

        private func synchronizePresentation() {
            guard isViewLoaded, view.window != nil else { return }

            guard isPresented?.wrappedValue == true else {
                if searchController.isActive {
                    searchController.isActive = false
                } else {
                    detach()
                }
                return
            }

            guard let navigationController,
                  let navigationItem = navigationController.topViewController?.navigationItem
            else { return }

            if installedNavigationItem !== navigationItem {
                detach()
                previousSearchController = navigationItem.searchController
                previousHidesSearchBarWhenScrolling = navigationItem.hidesSearchBarWhenScrolling
                previousSearchBarPlacement = navigationItem.preferredSearchBarPlacement
                if #available(iOS 26.0, *) {
                    previousAllowsToolbarIntegration =
                        navigationItem.searchBarPlacementAllowsToolbarIntegration
                    navigationItem.searchBarPlacementAllowsToolbarIntegration = false
                }
                navigationItem.preferredSearchBarPlacement = .stacked
                navigationItem.searchController = searchController
                navigationItem.hidesSearchBarWhenScrolling = false
                installedNavigationItem = navigationItem
                navigationController.topViewController?.definesPresentationContext = true
            }

            guard !searchController.isActive, presentationTask == nil else { return }
            presentationTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }

                self.presentationTask = nil
                guard !Task.isCancelled,
                      self.isPresented?.wrappedValue == true
                else { return }

                self.searchController.isActive = true
                if #unavailable(iOS 26.0) {
                    self.searchController.searchBar.setShowsCancelButton(
                        true,
                        animated: false
                    )
                }
                self.searchController.searchBar.becomeFirstResponder()
            }
        }

        private func configureLegacySearchBar() {
            searchController.automaticallyShowsCancelButton = true
            if searchController.isActive {
                searchController.searchBar.setShowsCancelButton(true, animated: false)
            }
        }
    }
}
