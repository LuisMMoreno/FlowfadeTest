import Foundation
import Combine

/// Manages the playback queue with smart shuffle and history tracking.
@MainActor
final class QueueManager: ObservableObject {

    static let shared = QueueManager()

    // MARK: - Published State

    @Published var queue: [Song] = []
    @Published var currentIndex: Int = -1
    @Published var isShuffleOn: Bool = false
    @Published var repeatMode: RepeatMode = .off

    // MARK: - History for Smart Shuffle

    private var playHistory: [UUID] = []
    private var originalQueue: [Song] = [] // Before shuffle

    enum RepeatMode {
        case off
        case all
    }

    // MARK: - Computed Properties

    var currentSong: Song? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var hasNext: Bool {
        if repeatMode == .all && !queue.isEmpty { return true }
        return currentIndex < queue.count - 1
    }

    var hasPrevious: Bool {
        return currentIndex > 0
    }

    var upcomingSongs: [Song] {
        guard currentIndex >= 0, currentIndex < queue.count - 1 else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    // MARK: - Queue Management

    /// Set the queue and start playing from a specific index
    func setQueue(_ songs: [Song], startAt index: Int = 0) {
        originalQueue = songs
        if isShuffleOn {
            queue = smartShuffle(songs, startWith: songs[safe: index])
            currentIndex = 0
        } else {
            queue = songs
            currentIndex = index
        }
    }

    /// Add a song to the end of the queue
    func addToQueue(_ song: Song) {
        queue.append(song)
        originalQueue.append(song)
    }

    /// Add a song to play next (after current)
    func playNext(_ song: Song) {
        let insertIndex = currentIndex + 1
        if insertIndex <= queue.count {
            queue.insert(song, at: insertIndex)
        } else {
            queue.append(song)
        }
    }

    /// Remove a song from the queue at a specific index
    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            // Current song removed — adjust
            currentIndex = min(currentIndex, queue.count - 1)
        }
    }

    // MARK: - Navigation

    /// Move to the next song in the queue
    /// Returns the next song, or nil if at end
    func next() -> Song? {
        // Record current song in history
        if let current = currentSong {
            recordHistory(current)
        }

        if currentIndex < queue.count - 1 {
            currentIndex += 1
            return currentSong
        } else if repeatMode == .all && !queue.isEmpty {
            // Wrap around
            if isShuffleOn {
                queue = smartShuffle(originalQueue, startWith: nil)
            }
            currentIndex = 0
            return currentSong
        }
        return nil
    }

    /// Move to the previous song
    /// Returns the previous song, or nil if at beginning
    func previous() -> Song? {
        if currentIndex > 0 {
            currentIndex -= 1
            return currentSong
        }
        return nil
    }

    // MARK: - Shuffle

    /// Toggle shuffle mode
    func toggleShuffle() {
        isShuffleOn.toggle()
        if isShuffleOn {
            let current = currentSong
            queue = smartShuffle(originalQueue, startWith: current)
            currentIndex = 0
        } else {
            // Restore original order
            let current = currentSong
            queue = originalQueue
            if let current = current, let idx = queue.firstIndex(where: { $0.id == current.id }) {
                currentIndex = idx
            }
        }
    }

    /// Smart shuffle algorithm:
    /// 1. Exclude recently played songs
    /// 2. Penalize same-artist proximity
    /// 3. Weighted random selection
    private func smartShuffle(_ songs: [Song], startWith: Song?) -> [Song] {
        guard songs.count > 1 else { return songs }

        var result: [Song] = []
        var remaining = songs
        var recentArtists: [String] = []

        // Put the starting song first if specified
        if let start = startWith, let idx = remaining.firstIndex(where: { $0.id == start.id }) {
            result.append(remaining.remove(at: idx))
            recentArtists.append(start.artist)
        }

        // Build history set for exclusion
        let historyLimit = min(
            songs.count / Constants.shuffleHistoryDepthFraction,
            Constants.shuffleMaxHistory
        )
        let recentIDs = Set(playHistory.suffix(historyLimit))

        while !remaining.isEmpty {
            // Calculate weights for each candidate
            var weights: [Double] = remaining.map { song in
                var weight = 1.0

                // Penalize recently played
                if recentIDs.contains(song.id) {
                    weight *= 0.3
                }

                // Penalize same artist as recent picks
                let artistPenaltyDepth = min(Constants.shuffleArtistPenaltyDepth, recentArtists.count)
                let recentArtistSlice = recentArtists.suffix(artistPenaltyDepth)
                if recentArtistSlice.contains(song.artist) && song.artist != "Unknown Artist" {
                    weight *= 0.4
                }

                return weight
            }

            // Normalize weights
            let totalWeight = weights.reduce(0, +)
            if totalWeight > 0 {
                weights = weights.map { $0 / totalWeight }
            }

            // Weighted random selection
            let selectedIndex = weightedRandomIndex(weights: weights)
            let selected = remaining.remove(at: selectedIndex)
            result.append(selected)
            recentArtists.append(selected.artist)
        }

        return result
    }

    private func weightedRandomIndex(weights: [Double]) -> Int {
        let random = Double.random(in: 0..<1)
        var cumulative = 0.0
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if random < cumulative {
                return index
            }
        }
        return weights.count - 1
    }

    private func recordHistory(_ song: Song) {
        playHistory.append(song.id)
        // Keep history bounded
        if playHistory.count > 50 {
            playHistory.removeFirst(playHistory.count - 50)
        }
    }

    // MARK: - State Persistence

    func getStateForPersistence() -> (songIDs: [UUID], index: Int, shuffle: Bool) {
        return (
            songIDs: queue.map { $0.id },
            index: currentIndex,
            shuffle: isShuffleOn
        )
    }

    func restoreState(queue: [Song], index: Int, shuffle: Bool) {
        self.queue = queue
        self.originalQueue = queue
        self.currentIndex = index
        self.isShuffleOn = shuffle
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
