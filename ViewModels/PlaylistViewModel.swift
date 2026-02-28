import Foundation
import SwiftData

/// ViewModel for playlist CRUD operations.
@MainActor
final class PlaylistViewModel: ObservableObject {

    @Published var playlists: [Playlist] = []

    // MARK: - Fetch

    func fetchPlaylists(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.dateCreated, order: .reverse)]
        )
        playlists = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - CRUD

    func createPlaylist(name: String, modelContext: ModelContext) {
        let playlist = Playlist(name: name)
        modelContext.insert(playlist)
        try? modelContext.save()
        fetchPlaylists(modelContext: modelContext)
    }

    func renamePlaylist(_ playlist: Playlist, to name: String, modelContext: ModelContext) {
        playlist.name = name
        try? modelContext.save()
        fetchPlaylists(modelContext: modelContext)
    }

    func deletePlaylist(_ playlist: Playlist, modelContext: ModelContext) {
        modelContext.delete(playlist)
        try? modelContext.save()
        fetchPlaylists(modelContext: modelContext)
    }

    func deletePlaylists(at offsets: IndexSet, modelContext: ModelContext) {
        for index in offsets {
            modelContext.delete(playlists[index])
        }
        try? modelContext.save()
        fetchPlaylists(modelContext: modelContext)
    }

    // MARK: - Song Management

    func addSong(_ song: Song, to playlist: Playlist, modelContext: ModelContext) {
        guard !playlist.songIDs.contains(song.id) else { return }
        playlist.songIDs.append(song.id)
        try? modelContext.save()
    }

    func removeSong(at index: Int, from playlist: Playlist, modelContext: ModelContext) {
        guard index < playlist.songIDs.count else { return }
        playlist.songIDs.remove(at: index)
        try? modelContext.save()
    }

    func moveSongs(from source: IndexSet, to destination: Int, in playlist: Playlist, modelContext: ModelContext) {
        playlist.songIDs.move(fromOffsets: source, toOffset: destination)
        try? modelContext.save()
    }

    /// Resolve song IDs to Song objects in order
    func songsInPlaylist(_ playlist: Playlist, modelContext: ModelContext) -> [Song] {
        return PersistenceService.resolveSongs(ids: playlist.songIDs, modelContext: modelContext)
    }
}
