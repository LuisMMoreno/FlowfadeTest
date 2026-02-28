import Foundation
import SwiftData

/// Handles SwiftData container setup and playback state persistence.
struct PersistenceService {

    /// Save the current playback state
    static func savePlaybackState(
        modelContext: ModelContext,
        audioEngine: AudioEngine,
        queueManager: QueueManager
    ) {
        let queueState = queueManager.getStateForPersistence()

        // Try to fetch existing state
        let descriptor = FetchDescriptor<PlaybackState>()
        let existingStates = (try? modelContext.fetch(descriptor)) ?? []

        let state: PlaybackState
        if let existing = existingStates.first {
            state = existing
        } else {
            state = PlaybackState()
            modelContext.insert(state)
        }

        state.currentSongID = audioEngine.currentSong?.id
        state.currentTime = audioEngine.currentTime
        state.queueSongIDs = queueState.songIDs
        state.queueIndex = queueState.index
        state.isShuffleOn = queueState.shuffle
        state.crossfadeDuration = audioEngine.crossfadeDuration
        state.isCrossfadeEnabled = audioEngine.isCrossfadeEnabled

        try? modelContext.save()
    }

    /// Load the saved playback state
    static func loadPlaybackState(modelContext: ModelContext) -> PlaybackState? {
        let descriptor = FetchDescriptor<PlaybackState>()
        return try? modelContext.fetch(descriptor).first
    }

    /// Resolve song IDs to Song objects
    static func resolveSongs(ids: [UUID], modelContext: ModelContext) -> [Song] {
        let descriptor = FetchDescriptor<Song>()
        guard let allSongs = try? modelContext.fetch(descriptor) else { return [] }

        let songMap = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })
        return ids.compactMap { songMap[$0] }
    }
}
