import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            LibraryView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .recordings(let filter):
                        RecordingListView(filter: filter)
                    case .recentlyDeleted:
                        RecentlyDeletedView()
                    case .detail(let recordingID):
                        RecordingDetailView(recordingID: recordingID)
                    }
                }
        }
        .sheet(isPresented: $router.presentsRecorder) {
            RecordingSheet { result, title in
                completeRecording(result, title: title)
            }
            .presentationDetents([.height(320), .large])
            .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            router.handle(
                url,
                recentRecordingID: fetchMostRecentActiveRecordingID()
            )
        }
        .task {
            let isActive = scenePhase == .active
            services.processor.setApplicationActive(isActive)
            if isActive {
                consumePendingIntent()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                services.processor.setApplicationActive(true)
                consumePendingIntent()
            case .inactive, .background:
                services.processor.setApplicationActive(false)
            @unknown default:
                services.processor.setApplicationActive(false)
            }
        }
        .alert(
            "Couldn't Complete the Action",
            isPresented: Binding(
                get: { services.operationErrorMessage != nil },
                set: { if !$0 { services.operationErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(services.operationErrorMessage ?? "")
        }
    }

    @discardableResult
    private func completeRecording(_ result: RecordedAudio, title: String) -> Bool {
        let recording = AudioRecording(
            title: title,
            duration: result.duration,
            audioRelativePath: result.relativePath,
            processingState: .ready,
            waveform: result.waveform
        )
        modelContext.insert(recording)

        for draft in result.markers {
            let marker = RecordingMarker(
                timestamp: draft.timestamp,
                title: String(localized: "Marker"),
                recording: recording
            )
            modelContext.insert(marker)
            recording.markers.append(marker)
        }

        guard services.save(modelContext) else {
            return false
        }
        router.presentsRecorder = false
        router.open(recording.id)

        services.processor.enqueue(recording, in: modelContext)
        return true
    }

    private func consumePendingIntent() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: AppIntentKeys.startRecording) {
            defaults.removeObject(forKey: AppIntentKeys.startRecording)
            router.startRecording()
        } else if defaults.bool(forKey: AppIntentKeys.openRecent) {
            defaults.removeObject(forKey: AppIntentKeys.openRecent)
            if let id = fetchMostRecentActiveRecordingID() {
                router.open(id)
            }
        }
    }

    private func fetchMostRecentActiveRecordingID() -> UUID? {
        var descriptor = FetchDescriptor<AudioRecording>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.id
    }

}
