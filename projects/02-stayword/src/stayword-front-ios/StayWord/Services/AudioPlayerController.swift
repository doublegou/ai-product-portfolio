import AVFoundation
import MediaPlayer
import Observation

@MainActor
protocol AudioPlaybackService: AnyObject {
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var playbackRate: Float { get }
    var supportedPlaybackRates: [Float] { get }
    func load(_ recording: AudioRecording) throws
    func togglePlayback()
    func seek(to seconds: TimeInterval)
    func skip(by seconds: TimeInterval)
    func setPlaybackRate(_ rate: Float)
    func cyclePlaybackRate()
    func stop()
}

@MainActor
@Observable
final class AudioPlayerController: AudioPlaybackService {
    nonisolated static let availablePlaybackRates: [Float] = [
        0.5, 0.75, 1, 1.25, 1.5, 2,
    ]
    nonisolated static let playbackRateDefaultsKey = "audioPlaybackRate"

    private let fileStore: AudioFileStore
    private let userDefaults: UserDefaults
    private let player = AVPlayer()
    @ObservationIgnored nonisolated(unsafe) private var timeObserver: Any?
    @ObservationIgnored nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    private var loadedRecordingID: UUID?
    private var loadedTitle = ""

    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    private(set) var playbackRate: Float

    var supportedPlaybackRates: [Float] {
        Self.availablePlaybackRates
    }

    init(
        fileStore: AudioFileStore,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileStore = fileStore
        self.userDefaults = userDefaults
        let storedRate = userDefaults.object(
            forKey: Self.playbackRateDefaultsKey
        ) as? NSNumber
        self.playbackRate = Self.validatedPlaybackRate(
            storedRate?.floatValue
        )
        player.defaultRate = playbackRate
        configureRemoteCommands()
        observePlayback()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func load(_ recording: AudioRecording) throws {
        guard loadedRecordingID != recording.id else { return }
        let url = fileStore.url(for: recording.audioRelativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StayWordError.recordingNotFound
        }

        try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: []
        )
        try AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        player.defaultRate = playbackRate
        loadedRecordingID = recording.id
        loadedTitle = recording.title
        duration = recording.duration
        currentTime = 0
        isPlaying = false
        updateNowPlaying()
    }

    func togglePlayback() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
        updateNowPlaying()
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(0, seconds), duration)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
        updateNowPlaying()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setPlaybackRate(_ rate: Float) {
        guard Self.isSupportedPlaybackRate(rate) else { return }
        playbackRate = rate
        player.defaultRate = rate
        if isPlaying {
            player.rate = rate
        }
        userDefaults.set(rate, forKey: Self.playbackRateDefaultsKey)
        updateNowPlaying()
    }

    func cyclePlaybackRate() {
        guard !supportedPlaybackRates.isEmpty else { return }
        let currentIndex = supportedPlaybackRates.firstIndex {
            abs($0 - playbackRate) < 0.001
        } ?? 0
        let nextIndex = supportedPlaybackRates.index(
            after: currentIndex
        ) % supportedPlaybackRates.count
        setPlaybackRate(supportedPlaybackRates[nextIndex])
    }

    func stop() {
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
        currentTime = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func observePlayback() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                self.updateNowPlaying()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.togglePlayback()
            }
            return .success
        }
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skip(by: 15) }
            return .success
        }
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skip(by: -15) }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }

        commands.changePlaybackRateCommand.supportedPlaybackRates =
            Self.availablePlaybackRates.map { NSNumber(value: $0) }
        commands.changePlaybackRateCommand.isEnabled = true
        commands.changePlaybackRateCommand.addTarget { [weak self] event in
            guard
                let rateEvent = event as? MPChangePlaybackRateCommandEvent,
                Self.isSupportedPlaybackRate(rateEvent.playbackRate)
            else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                self?.setPlaybackRate(rateEvent.playbackRate)
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard loadedRecordingID != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: loadedTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }

    nonisolated static func validatedPlaybackRate(_ rate: Float?) -> Float {
        guard let rate, isSupportedPlaybackRate(rate) else { return 1 }
        return rate
    }

    nonisolated static func isSupportedPlaybackRate(_ rate: Float) -> Bool {
        availablePlaybackRates.contains { abs($0 - rate) < 0.001 }
    }

    nonisolated static func playbackRateLabel(
        _ rate: Float,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: rate)) ?? "1"
        return number + "×"
    }
}
