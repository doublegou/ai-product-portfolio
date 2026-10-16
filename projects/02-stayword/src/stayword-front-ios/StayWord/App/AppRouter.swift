import Observation
import SwiftUI

enum RecordingListFilter: Hashable {
    case all
    case favorites
    case folder(UUID)

    var title: LocalizedStringKey {
        switch self {
        case .all:
            "All Recordings"
        case .favorites:
            "Favorites"
        case .folder:
            "Folder"
        }
    }
}

enum AppRoute: Hashable {
    case recordings(RecordingListFilter)
    case recentlyDeleted
    case detail(UUID)
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var presentsRecorder = false

    func startRecording() {
        presentsRecorder = true
    }

    func open(_ recordingID: UUID) {
        path.append(.detail(recordingID))
    }

    func handle(_ url: URL, recentRecordingID: UUID?) {
        guard url.scheme == "stayword" else { return }

        switch url.host {
        case "recording":
            presentsRecorder = true
        case "recent":
            if let recentRecordingID {
                path.append(.detail(recentRecordingID))
            }
        default:
            break
        }
    }
}
