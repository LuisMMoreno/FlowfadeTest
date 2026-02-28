import SwiftUI
import SwiftData

/// Detail view for a single playlist — shows its songs with playback and editing.
struct PlaylistDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var queueManager: QueueManager

    @StateObject private var viewModel = PlaylistViewModel()

    let playlist: Playlist

    @State private var songs: [Song] = []
    @State private var showAddSongs = false

    var body: some View {
        Group {
            if songs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("No songs in this playlist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Add Songs") {
                        showAddSongs = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Play all button
                    Button {
                        playAll()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play All")
                            Spacer()
                            Text("\(songs.count) songs")
                                .foregroundStyle(.secondary)
                        }
                        .font(.headline)
                    }

                    ForEach(songs, id: \.id) { song in
                        SongRowView(
                            song: song,
                            isCurrentlyPlaying: audioEngine.currentSong?.id == song.id
                        )
                        .onTapGesture {
                            playSong(song)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.removeSong(at: index, from: playlist, modelContext: modelContext)
                        }
                        refreshSongs()
                    }
                    .onMove { source, destination in
                        viewModel.moveSongs(from: source, to: destination, in: playlist, modelContext: modelContext)
                        refreshSongs()
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSongs = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            if !songs.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showAddSongs) {
            AddSongsSheet(playlist: playlist)
        }
        .onAppear {
            refreshSongs()
        }
        .onChange(of: showAddSongs) { _, isShowing in
            if !isShowing {
                refreshSongs()
            }
        }
    }

    private func refreshSongs() {
        songs = viewModel.songsInPlaylist(playlist, modelContext: modelContext)
    }

    private func playSong(_ song: Song) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        queueManager.setQueue(songs, startAt: index)
        audioEngine.play(song: song)
    }

    private func playAll() {
        guard let first = songs.first else { return }
        playSong(first)
    }
}

// MARK: - Add Songs Sheet

struct AddSongsSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist

    @StateObject private var playlistVM = PlaylistViewModel()
    @State private var allSongs: [Song] = []
    @State private var searchText = ""

    private var filteredSongs: [Song] {
        let existingIDs = Set(playlist.songIDs)
        let available = allSongs.filter { !existingIDs.contains($0.id) }

        if searchText.isEmpty {
            return available
        }
        let query = searchText.lowercased()
        return available.filter {
            $0.displayTitle.lowercased().contains(query) ||
            $0.displayArtist.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredSongs, id: \.id) { song in
                HStack {
                    SongRowView(song: song, isCurrentlyPlaying: false)

                    Button {
                        playlistVM.addSong(song, to: playlist, modelContext: modelContext)
                        fetchSongs()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search songs")
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            fetchSongs()
        }
    }

    private func fetchSongs() {
        let descriptor = FetchDescriptor<Song>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        allSongs = (try? modelContext.fetch(descriptor)) ?? []
    }
}
