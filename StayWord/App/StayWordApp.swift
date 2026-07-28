import SwiftData
import SwiftUI

@main
struct StayWordApp: App {
    @State private var router = AppRouter()
    @State private var services = AppServices()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            RecordingFolder.self,
            AudioRecording.self,
            TranscriptSegment.self,
            RecordingMarker.self,
        ])

        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create StayWord data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(services)
        }
        .modelContainer(modelContainer)
    }
}
