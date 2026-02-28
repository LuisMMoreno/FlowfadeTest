import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// ViewModel for the song library — manages import, fetch, search, and deletion.
@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var songs: [Song] = []
    @Published var searchText: String = ""
    @Published var isImporting: Bool = false
    @Published var importProgress: String = ""

    var filteredSongs: [Song] {
        if searchText.isEmpty {
            return songs
        }
        let query = searchText.lowercased()
        return songs.filter {
            $0.displayTitle.lowercased().contains(query) ||
            $0.displayArtist.lowercased().contains(query)
        }
    }

    // MARK: - Fetch Songs

    func fetchSongs(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Song>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        songs = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Import

    func importFiles(urls: [URL], modelContext: ModelContext) async {
        isImporting = true
        importProgress = "Importing \(urls.count) file(s)..."

        let imported = await FileImportService.importFiles(from: urls, modelContext: modelContext)

        importProgress = "Imported \(imported.count) song(s)"
        fetchSongs(modelContext: modelContext)

        // Clear progress after a delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        isImporting = false
        importProgress = ""
    }

    // MARK: - Delete

    func deleteSong(_ song: Song, modelContext: ModelContext) {
        FileImportService.deleteFile(for: song)
        modelContext.delete(song)
        try? modelContext.save()
        fetchSongs(modelContext: modelContext)
    }

    func deleteSongs(at offsets: IndexSet, modelContext: ModelContext) {
        let songsToDelete = offsets.map { filteredSongs[$0] }
        for song in songsToDelete {
            FileImportService.deleteFile(for: song)
            modelContext.delete(song)
        }
        try? modelContext.save()
        fetchSongs(modelContext: modelContext)
    }

    // MARK: - Play

    func playSong(
        _ song: Song,
        audioEngine: AudioEngine,
        queueManager: QueueManager
    ) {
        let allSongs = filteredSongs
        guard let index = allSongs.firstIndex(where: { $0.id == song.id }) else { return }

        queueManager.setQueue(allSongs, startAt: index)
        audioEngine.play(song: song)
        setupAutoAdvance(audioEngine: audioEngine, queueManager: queueManager)
    }

    func playAll(
        audioEngine: AudioEngine,
        queueManager: QueueManager
    ) {
        guard let first = filteredSongs.first else { return }
        playSong(first, audioEngine: audioEngine, queueManager: queueManager)
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
}
