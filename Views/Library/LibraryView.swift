import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The main library view — shows all imported songs with search and import.
struct LibraryView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var queueManager: QueueManager

    @StateObject private var viewModel = LibraryViewModel()
    @State private var showFileImporter = false
    @State private var songToEdit: Song?
    @State private var songForPlaylist: Song?
    @State private var showPlaylistPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.songs.isEmpty {
                    emptyStateView
                } else {
                    songListView
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }

                if !viewModel.songs.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            viewModel.playAll(
                                audioEngine: audioEngine,
                                queueManager: queueManager
                            )
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                        }
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search songs")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await viewModel.importFiles(urls: urls, modelContext: modelContext)
                    }
                case .failure(let error):
                    print("File import error: \(error)")
                }
            }
            .sheet(item: $songToEdit) { song in
                MetadataEditorSheet(song: song)
            }
            .overlay(alignment: .bottom) {
                if viewModel.isImporting {
                    importProgressView
                }
            }
        }
        .onAppear {
            viewModel.fetchSongs(modelContext: modelContext)
        }
    }

    // MARK: - Song List

    private var songListView: some View {
        List {
            ForEach(viewModel.filteredSongs, id: \.id) { song in
                SongRowView(
                    song: song,
                    isCurrentlyPlaying: audioEngine.currentSong?.id == song.id
                )
                .onTapGesture {
                    viewModel.playSong(
                        song,
                        audioEngine: audioEngine,
                        queueManager: queueManager
                    )
                }
                .contextMenu {
                    Button {
                        songToEdit = song
                    } label: {
                        Label("Edit Info", systemImage: "pencil")
                    }

                    Button {
                        songForPlaylist = song
                        showPlaylistPicker = true
                    } label: {
                        Label("Add to Playlist", systemImage: "text.badge.plus")
                    }

                    Button {
                        queueManager.playNext(song)
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }

                    Button {
                        queueManager.addToQueue(song)
                    } label: {
                        Label("Add to Queue", systemImage: "text.append")
                    }

                    Divider()

                    Button(role: .destructive) {
                        viewModel.deleteSong(song, modelContext: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.deleteSong(song, modelContext: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "music.note.house.fill")
                .font(.system(size: 70))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Your Library is Empty")
                .font(.title2)
                .fontWeight(.bold)

            Text("Tap **+** to import music files\nfrom your device or iCloud")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showFileImporter = true
            } label: {
                Label("Import Music", systemImage: "folder.badge.plus")
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

    // MARK: - Import Progress

    private var importProgressView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(viewModel.importProgress)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 80)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring, value: viewModel.isImporting)
    }
}
