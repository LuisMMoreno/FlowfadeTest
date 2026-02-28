import Foundation
import AVFoundation
import Combine
import SwiftData

/// The core audio engine for Flowfade.
/// Manages dual-player crossfade playback using AVAudioEngine.
///
/// Architecture:
/// - Two AVAudioPlayerNodes alternate as "current" and "next"
/// - A DisplayLink-style timer drives smooth volume transitions
/// - CrossfadeAnalyzer determines adaptive timing per song
@MainActor
final class AudioEngine: ObservableObject {

    static let shared = AudioEngine()

    // MARK: - Published State

    @Published var isPlaying: Bool = false
    @Published var currentSong: Song?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isCrossfading: Bool = false
    @Published var crossfadeDuration: TimeInterval = Constants.defaultCrossfadeDuration
    @Published var isCrossfadeEnabled: Bool = true

    // MARK: - Audio Engine Components

    private var engine: AVAudioEngine
    private var playerNodeA: AVAudioPlayerNode
    private var playerNodeB: AVAudioPlayerNode
    private var mixerA: AVAudioMixerNode
    private var mixerB: AVAudioMixerNode

    /// Which player is currently the "active" one
    private var isPlayerAActive: Bool = true

    private var activePlayer: AVAudioPlayerNode { isPlayerAActive ? playerNodeA : playerNodeB }
    private var inactivePlayer: AVAudioPlayerNode { isPlayerAActive ? playerNodeB : playerNodeA }
    private var activeMixer: AVAudioMixerNode { isPlayerAActive ? mixerA : mixerB }
    private var inactiveMixer: AVAudioMixerNode { isPlayerAActive ? mixerB : mixerA }

    // MARK: - File References

    private var currentAudioFile: AVAudioFile?
    private var nextAudioFile: AVAudioFile?
    private var currentStartFrame: AVAudioFramePosition = 0

    // MARK: - Crossfade State

    private var crossfadeTimer: Timer?
    private var crossfadeProgress: Float = 0
    private var effectiveCrossfadeDuration: TimeInterval = 6.0
    private var crossfadeStartTime: Date?

    // MARK: - Playback Tracking

    private var playbackTimer: Timer?
    private var pendingSeek: TimeInterval?

    // MARK: - Callbacks

    var onSongFinished: (() -> Void)?

    // MARK: - Init

    private init() {
        engine = AVAudioEngine()
        playerNodeA = AVAudioPlayerNode()
        playerNodeB = AVAudioPlayerNode()
        mixerA = AVAudioMixerNode()
        mixerB = AVAudioMixerNode()

        setupEngine()
    }

    private func setupEngine() {
        engine.attach(playerNodeA)
        engine.attach(playerNodeB)
        engine.attach(mixerA)
        engine.attach(mixerB)

        // Connect players → mixers → main mixer → output
        let mainMixer = engine.mainMixerNode

        // Use a common format
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

        engine.connect(playerNodeA, to: mixerA, format: format)
        engine.connect(playerNodeB, to: mixerB, format: format)
        engine.connect(mixerA, to: mainMixer, format: format)
        engine.connect(mixerB, to: mainMixer, format: format)

        // Start with mixer B silent
        mixerB.outputVolume = 0

        do {
            try engine.start()
        } catch {
            print("AudioEngine failed to start: \(error)")
        }
    }

    // MARK: - Public Playback API

    /// Play a song from the beginning
    func play(song: Song, startTime: TimeInterval = 0) {
        stopAll()

        guard let audioFile = loadAudioFile(for: song) else {
            print("Cannot load audio file for: \(song.displayTitle)")
            return
        }

        currentSong = song
        currentAudioFile = audioFile
        duration = song.duration
        isPlayerAActive = true

        // Reconnect with the file's format
        reconnectPlayer(playerNodeA, mixer: mixerA, format: audioFile.processingFormat)

        // Calculate start frame if resuming
        let startFrame = AVAudioFramePosition(startTime * audioFile.processingFormat.sampleRate)
        let totalFrames = AVAudioFrameCount(audioFile.length - startFrame)

        guard totalFrames > 0 else { return }

        audioFile.framePosition = startFrame
        currentStartFrame = startFrame

        playerNodeA.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: totalFrames,
            at: nil
        )

        mixerA.outputVolume = 1.0
        mixerB.outputVolume = 0.0

        playerNodeA.play()
        isPlaying = true
        currentTime = startTime

        startPlaybackTracking()
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Pause playback
    func pause() {
        activePlayer.pause()
        if isCrossfading {
            inactivePlayer.pause()
        }
        isPlaying = false
        stopPlaybackTracking()
    }

    /// Resume playback
    func resume() {
        activePlayer.play()
        if isCrossfading {
            inactivePlayer.play()
        }
        isPlaying = true
        startPlaybackTracking()
    }

    /// Stop all playback
    func stop() {
        stopAll()
        currentSong = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isCrossfading = false
    }

    /// Seek to a specific time in the current song
    func seek(to time: TimeInterval) {
        guard let song = currentSong, let file = currentAudioFile else { return }

        let wasPlaying = isPlaying

        activePlayer.stop()

        let frame = AVAudioFramePosition(time * file.processingFormat.sampleRate)
        let remainingFrames = AVAudioFrameCount(file.length - frame)

        guard remainingFrames > 0 else { return }

        file.framePosition = frame
        currentStartFrame = frame

        activePlayer.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: remainingFrames,
            at: nil
        )

        currentTime = time

        if wasPlaying {
            activePlayer.play()
        }
    }

    /// Prepare the next song for crossfade transition
    func prepareNext(song: Song) async {
        guard let audioFile = loadAudioFile(for: song) else { return }
        nextAudioFile = audioFile

        // Analyze tail of current song for adaptive crossfade
        if isCrossfadeEnabled, let currentSong = currentSong {
            let multiplier = await CrossfadeAnalyzer.analyzeTail(
                of: currentSong.fileURL,
                baseDuration: crossfadeDuration
            )
            effectiveCrossfadeDuration = crossfadeDuration * multiplier
        } else {
            effectiveCrossfadeDuration = crossfadeDuration
        }
    }

    /// Begin crossfade transition to the next song
    func beginCrossfade(to nextSong: Song) {
        guard isCrossfadeEnabled else {
            // No crossfade — just play next song directly
            play(song: nextSong)
            return
        }

        guard let nextFile = nextAudioFile else {
            play(song: nextSong)
            return
        }

        isCrossfading = true

        // Reconnect inactive player with the next file's format
        reconnectPlayer(inactivePlayer, mixer: inactiveMixer, format: nextFile.processingFormat)

        // Schedule next song from beginning
        nextFile.framePosition = 0
        inactivePlayer.scheduleFile(nextFile, at: nil)

        // Set initial volumes
        inactiveMixer.outputVolume = 0
        // activeMixer volume stays at current level

        // Start the incoming player
        inactivePlayer.play()

        // Start crossfade timer
        crossfadeProgress = 0
        crossfadeStartTime = Date()
        startCrossfadeTimer()

        // Update current song info
        currentSong = nextSong
        currentAudioFile = nextFile
        currentStartFrame = 0
        duration = nextSong.duration
        currentTime = 0
    }

    /// Save current playback state for persistence
    func saveCurrentState() {
        // This is called by the app delegate / scene delegate
        // The actual saving is handled by the ViewModel
    }

    // MARK: - Private Methods

    private func loadAudioFile(for song: Song) -> AVAudioFile? {
        let url = song.fileURL
        do {
            return try AVAudioFile(forReading: url)
        } catch {
            print("Cannot load audio file at \(url): \(error)")
            return nil
        }
    }

    private func reconnectPlayer(
        _ player: AVAudioPlayerNode,
        mixer: AVAudioMixerNode,
        format: AVAudioFormat
    ) {
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: mixer, format: format)
    }

    private func stopAll() {
        stopPlaybackTracking()
        stopCrossfadeTimer()

        playerNodeA.stop()
        playerNodeB.stop()

        isCrossfading = false
    }

    // MARK: - Playback Time Tracking

    private func startPlaybackTracking() {
        stopPlaybackTracking()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackTime()
            }
        }
    }

    private func stopPlaybackTracking() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updatePlaybackTime() {
        guard let file = currentAudioFile,
              let nodeTime = activePlayer.lastRenderTime,
              let playerTime = activePlayer.playerTime(forNodeTime: nodeTime) else {
            return
        }

        let sampleRate = file.processingFormat.sampleRate
        let elapsedFrames = playerTime.sampleTime
        currentTime = Double(currentStartFrame + elapsedFrames) / sampleRate

        // Check if we need to start crossfade
        if isCrossfadeEnabled && !isCrossfading {
            let timeRemaining = duration - currentTime
            if timeRemaining <= effectiveCrossfadeDuration && timeRemaining > 0 {
                onSongFinished?()
            }
        }

        // Check if song finished (without crossfade)
        if currentTime >= duration - 0.1 && !isCrossfading {
            onSongFinished?()
        }
    }

    // MARK: - Crossfade Timer

    private func startCrossfadeTimer() {
        stopCrossfadeTimer()
        crossfadeTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.crossfadeTimerInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateCrossfade()
            }
        }
    }

    private func stopCrossfadeTimer() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
    }

    private func updateCrossfade() {
        guard let startTime = crossfadeStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let progress = Float(elapsed / effectiveCrossfadeDuration)

        if progress >= 1.0 {
            // Crossfade complete
            finishCrossfade()
            return
        }

        crossfadeProgress = progress

        // Apply equal-power curves
        let outVolume = AudioMath.fadeOutVolume(progress: progress)
        let inVolume = AudioMath.fadeInVolume(progress: progress)

        if isPlayerAActive {
            mixerA.outputVolume = outVolume
            mixerB.outputVolume = inVolume
        } else {
            mixerB.outputVolume = outVolume
            mixerA.outputVolume = inVolume
        }
    }

    private func finishCrossfade() {
        stopCrossfadeTimer()

        // Stop the old player
        activePlayer.stop()
        activeMixer.outputVolume = 0

        // Swap players
        isPlayerAActive.toggle()

        // Set new active player to full volume
        activeMixer.outputVolume = 1.0

        isCrossfading = false
        crossfadeProgress = 0
        crossfadeStartTime = nil
    }
}
