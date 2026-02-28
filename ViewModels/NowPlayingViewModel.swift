import Foundation
import SwiftUI
import SwiftData

/// ViewModel for the Now Playing screen — binds to AudioEngine and QueueManager.
@MainActor
final class NowPlayingViewModel: ObservableObject {

    @Published var isSeeking: Bool = false
    @Published var seekValue: TimeInterval = 0

    // MARK: - Playback Controls

    func togglePlayPause(audioEngine: AudioEngine) {
        audioEngine.togglePlayPause()
    }

    func skipNext(audioEngine: AudioEngine, queueManager: QueueManager) {
        if let nextSong = queueManager.next() {
            Task {
                await audioEngine.prepareNext(song: nextSong)
                audioEngine.beginCrossfade(to: nextSong)
            }
        }
    }

    func skipPrevious(audioEngine: AudioEngine, queueManager: QueueManager) {
        // If more than 3 seconds into the song, restart. Otherwise go to previous.
        if audioEngine.currentTime > 3 {
            audioEngine.seek(to: 0)
        } else if let prevSong = queueManager.previous() {
            audioEngine.play(song: prevSong)
        }
    }

    func seek(to time: TimeInterval, audioEngine: AudioEngine) {
        audioEngine.seek(to: time)
    }

    func toggleShuffle(queueManager: QueueManager) {
        queueManager.toggleShuffle()
    }

    // MARK: - State Restoration

    func restoreState(
        modelContext: ModelContext,
        audioEngine: AudioEngine,
        queueManager: QueueManager
    ) {
        guard let savedState = PersistenceService.loadPlaybackState(modelContext: modelContext) else {
            return
        }

        // Restore settings
        audioEngine.crossfadeDuration = savedState.crossfadeDuration
        audioEngine.isCrossfadeEnabled = savedState.isCrossfadeEnabled

        // Restore queue
        let songs = PersistenceService.resolveSongs(
            ids: savedState.queueSongIDs,
            modelContext: modelContext
        )

        guard !songs.isEmpty else { return }

        queueManager.restoreState(
            queue: songs,
            index: savedState.queueIndex,
            shuffle: savedState.isShuffleOn
        )

        // Restore current song at the exact position
        if let songID = savedState.currentSongID,
           let song = songs.first(where: { $0.id == songID }) {
            audioEngine.play(song: song, startTime: savedState.currentTime)
            audioEngine.pause() // Don't auto-play on restore
        }

        // Setup auto-advance
        setupAutoAdvance(audioEngine: audioEngine, queueManager: queueManager)
    }

    func saveState(
        modelContext: ModelContext,
        audioEngine: AudioEngine,
        queueManager: QueueManager
    ) {
        PersistenceService.savePlaybackState(
            modelContext: modelContext,
            audioEngine: audioEngine,
            queueManager: queueManager
        )
    }

    private func setupAutoAdvance(audioEngine: AudioEngine, queueManager: QueueManager) {
        audioEngine.onSongFinished = { [weak audioEngine, weak queueManager] in
            guard let engine = audioEngine, let queue = queueManager else { return }
            Task { @MainActor in
                if let nextSong = queue.next() {
                    await engine.prepareNext(song: nextSong)
                    engine.beginCrossfade(to: nextSong)
                } else {
                    engine.stop()
                }
            }
        }
    }

    // MARK: - Time Formatting

    static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
