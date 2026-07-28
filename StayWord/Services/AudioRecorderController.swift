import AVFAudio
import Foundation
import Observation

@MainActor
protocol AudioRecordingService: AnyObject {
    var elapsed: TimeInterval { get }
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    func start() async throws
    func pause()
    func resume()
    func addMarker()
    func finish() async throws -> RecordedAudio
    func cancel()
}

@MainActor
@Observable
final class AudioRecorderController: NSObject, AudioRecordingService, @preconcurrency AVAudioRecorderDelegate {
    private let fileStore: AudioFileStore
    private let liveActivity = RecordingLiveActivityService()
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var markerDrafts: [MarkerDraft] = []
    private var shouldResumeAfterInterruption = false
    private var isFinalizing = false
    @ObservationIgnored nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var routeObserver: NSObjectProtocol?

    var elapsed: TimeInterval = 0
    var isRecording = false
    var isPaused = false
    var amplitudes: [Double] = Array(repeating: 0.08, count: 48)
    var interruptionMessage: String?
    var needsFinishingAfterFailure = false

    init(fileStore: AudioFileStore) {
        self.fileStore = fileStore
        super.init()
        observeAudioSession()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    func start() async throws {
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard permitted else {
            throw StayWordError.microphoneDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)

        let url = try fileStore.newRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw StayWordError.recordingUnavailable
        }

        self.recorder = recorder
        elapsed = 0
        isRecording = true
        isPaused = false
        amplitudes = Array(repeating: 0.08, count: 48)
        markerDrafts.removeAll()
        interruptionMessage = nil
        startMetering()
        await liveActivity.start(recordingID: UUID(), title: String(localized: "New Recording"))
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        isPaused = true
        Task { await liveActivity.update(isPaused: true, elapsed: elapsed) }
    }

    func resume() {
        guard isRecording, isPaused else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            guard recorder?.record() == true else {
                throw StayWordError.recordingUnavailable
            }
            isPaused = false
            interruptionMessage = nil
            Task { await liveActivity.update(isPaused: false, elapsed: elapsed) }
        } catch {
            stopAndPreserveRecording(
                message: String(localized: "Recording couldn't resume. The audio recorded so far will be saved.")
            )
        }
    }

    func addMarker() {
        guard isRecording else { return }
        markerDrafts.append(MarkerDraft(timestamp: elapsed))
    }

    func finish() async throws -> RecordedAudio {
        guard let recorder else {
            throw StayWordError.recordingUnavailable
        }

        isFinalizing = true
        defer { isFinalizing = false }
        let url = recorder.url
        let duration = recorder.currentTime
        recorder.stop()
        stopMetering()
        let waveform = try WaveformExtractor.extract(from: url)
        resetState()
        await liveActivity.end()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        return RecordedAudio(
            relativePath: fileStore.relativePath(for: url),
            duration: max(duration, 0.1),
            waveform: waveform,
            markers: markerDrafts
        )
    }

    func cancel() {
        isFinalizing = true
        let url = recorder?.url
        recorder?.stop()
        stopMetering()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        resetState()
        Task { await liveActivity.end() }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        isFinalizing = false
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(
            withTimeInterval: 0.05,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
                guard !self.isPaused else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0.04, min(1, pow(10, Double(power) / 30)))
                self.amplitudes.append(normalized)
                if self.amplitudes.count > 160 {
                    self.amplitudes.removeFirst(self.amplitudes.count - 160)
                }
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func resetState() {
        recorder = nil
        isRecording = false
        isPaused = false
        elapsed = 0
        shouldResumeAfterInterruption = false
        needsFinishingAfterFailure = false
    }

    private func observeAudioSession() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions =
                notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                guard
                    let self,
                    let rawType,
                    let type = AVAudioSession.InterruptionType(rawValue: rawType)
                else { return }

                if type == .began {
                    self.shouldResumeAfterInterruption =
                        self.isRecording && !self.isPaused
                    if self.shouldResumeAfterInterruption {
                        self.pause()
                    }
                    self.interruptionMessage = String(localized: "Recording paused by a system interruption.")
                } else if type == .ended, self.shouldResumeAfterInterruption {
                    self.shouldResumeAfterInterruption = false
                    let options = AVAudioSession.InterruptionOptions(
                        rawValue: rawOptions ?? 0
                    )

                    if options.contains(.shouldResume) {
                        self.resume()
                    } else {
                        self.stopAndPreserveRecording(
                            message: String(localized: "Recording couldn't continue after the interruption. The audio recorded so far will be saved.")
                        )
                    }
                }
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard
                    let self,
                    let rawReason,
                    AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
                else { return }
                self.interruptionMessage = String(localized: "The audio input route changed.")
            }
        }
    }

    private func stopAndPreserveRecording(message: String) {
        guard isRecording, !needsFinishingAfterFailure else { return }
        recorder?.pause()
        stopMetering()
        isPaused = true
        interruptionMessage = message
        needsFinishingAfterFailure = true
    }

    func acknowledgeFinishingAfterFailure() {
        needsFinishingAfterFailure = false
    }

    func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        guard isRecording, !isFinalizing else { return }
        stopAndPreserveRecording(
            message: flag
                ? String(localized: "Recording ended and the audio recorded so far will be saved.")
                : String(localized: "Recording stopped unexpectedly. The audio recorded so far will be saved.")
        )
    }

    func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: (any Error)?
    ) {
        guard !isFinalizing else { return }
        stopAndPreserveRecording(
            message: error?.localizedDescription
                ?? String(localized: "Recording stopped unexpectedly. The audio recorded so far will be saved.")
        )
    }
}
