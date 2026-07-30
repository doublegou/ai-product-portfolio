import CoreLocation
@preconcurrency import MapKit
import Observation
import SwiftData

@MainActor
@Observable
final class AppServices {
    let recorder: AudioRecorderController
    let player: AudioPlayerController
    let importer: AudioImportService
    let processor: ProcessingCoordinator
    let recordingTitleProvider: RecordingTitleProvider
    var operationErrorMessage: String?

    init() {
        let fileStore = AudioFileStore()
        self.recorder = AudioRecorderController(fileStore: fileStore)
        self.player = AudioPlayerController(fileStore: fileStore)
        self.importer = AudioImportService(fileStore: fileStore)
        #if DEBUG
        let summaryGenerationEnabled =
            ProcessInfo.processInfo.environment["STAYWORD_UI_TEST_DISABLE_SUMMARY"] != "1"
        #else
        let summaryGenerationEnabled = true
        #endif
        self.processor = ProcessingCoordinator(
            fileStore: fileStore,
            summaryGenerationEnabled: summaryGenerationEnabled
        )
        self.recordingTitleProvider = RecordingTitleProvider()
    }

    @discardableResult
    func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            report(error)
            return false
        }
    }

    func report(_ error: Error) {
        operationErrorMessage = error.localizedDescription
    }
}

@MainActor
final class RecordingTitleProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func suggestedTitle() async -> String {
        let fallback = String(localized: "New Recording")
        guard let location = await requestLocation() else {
            return fallback
        }

        if #available(iOS 26.0, *),
           let title = await modernPlaceName(for: location) {
            return title
        }

        return await legacyPlaceName(for: location) ?? fallback
    }

    private func requestLocation() async -> CLLocation? {
        guard locationContinuation == nil else {
            return nil
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                locationContinuation = continuation

                switch manager.authorizationStatus {
                case .notDetermined:
                    manager.requestWhenInUseAuthorization()
                case .authorizedAlways, .authorizedWhenInUse:
                    manager.requestLocation()
                case .denied, .restricted:
                    resumeLocationRequest(with: nil)
                @unknown default:
                    resumeLocationRequest(with: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeLocationRequest(with: nil)
            }
        }
    }

    @available(iOS 26.0, *)
    private func modernPlaceName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }

        do {
            request.preferredLocale = .autoupdatingCurrent
            return try await request.mapItems
                .lazy
                .compactMap(\.name)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        } catch {
            return nil
        }
    }

    private func legacyPlaceName(for location: CLLocation) async -> String? {
        do {
            let placemark = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: .autoupdatingCurrent
            ).first

            return [
                placemark?.name,
                placemark?.thoroughfare,
                placemark?.subLocality,
                placemark?.locality,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        } catch {
            return nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            resumeLocationRequest(with: nil)
        case .notDetermined:
            break
        @unknown default:
            resumeLocationRequest(with: nil)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        resumeLocationRequest(with: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resumeLocationRequest(with: nil)
    }

    private func resumeLocationRequest(with location: CLLocation?) {
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
}
