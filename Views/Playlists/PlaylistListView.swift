import SwiftUI
import SwiftData

/// List of all user-created playlists.
struct PlaylistListView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var queueManager: QueueManager

    @StateObject private var viewModel = PlaylistViewModel()
    @State private var showCreateSheet = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.playlists.isEmpty {
                    emptyState
                } else {
                    playlistsList
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newPlaylistName = ""
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .alert("New Playlist", isPresented: $showCreateSheet) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    if !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.createPlaylist(
                            name: newPlaylistName.trimmingCharacters(in: .whitespaces),
                            modelContext: modelContext
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear {
            viewModel.fetchPlaylists(modelContext: modelContext)
        }
    }

    private var playlistsList: some View {
        List {
            ForEach(viewModel.playlists, id: \.id) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 50, height: 50)

                            Image(systemName: "music.note.list")
                                .foregroundStyle(.white)
                                .font(.title3)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.body)
                                .fontWeight(.medium)

                            Text("\(playlist.songCount) song\(playlist.songCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                viewModel.deletePlaylists(at: offsets, modelContext: modelContext)
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("No Playlists Yet")
                .font(.title2)
                .fontWeight(.bold)

            Text("Create a playlist to organize\nyour favorite songs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                newPlaylistName = ""
                showCreateSheet = true
            } label: {
                Label("Create Playlist", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            Spacer()
        }
        .padding()
    }
}
