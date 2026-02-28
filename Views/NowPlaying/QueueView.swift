import SwiftUI

/// Shows the upcoming songs in the playback queue.
struct QueueView: View {

    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if queueManager.queue.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var queueList: some View {
        List {
            // Now Playing
            if let current = queueManager.currentSong {
                Section("Now Playing") {
                    SongRowView(song: current, isCurrentlyPlaying: true)
                }
            }

            // Up Next
            let upcoming = queueManager.upcomingSongs
            if !upcoming.isEmpty {
                Section("Up Next — \(upcoming.count) song\(upcoming.count == 1 ? "" : "s")") {
                    ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, song in
                        SongRowView(song: song, isCurrentlyPlaying: false)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    queueManager.removeFromQueue(at: queueManager.currentIndex + 1 + index)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Queue is Empty")
                .font(.title3)
                .fontWeight(.medium)

            Text("Play a song from your library\nto start building your queue")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
