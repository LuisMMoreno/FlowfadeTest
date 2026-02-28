import SwiftUI

/// Persistent mini player bar shown at the bottom of the tab view when a song is playing.
struct MiniPlayerView: View {

    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var queueManager: QueueManager
    @Binding var showNowPlaying: Bool

    var body: some View {
        if audioEngine.currentSong != nil {
            VStack(spacing: 0) {
                // Progress bar thin line
                GeometryReader { geo in
                    let progress = audioEngine.duration > 0
                        ? audioEngine.currentTime / audioEngine.duration
                        : 0

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.white.opacity(0.1))
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 2)

                // Content
                HStack(spacing: 12) {
                    ArtworkView(artworkData: audioEngine.currentSong?.artworkData, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioEngine.currentSong?.displayTitle ?? "")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text(audioEngine.currentSong?.displayArtist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Play / Pause
                    Button {
                        audioEngine.togglePlayPause()
                    } label: {
                        Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }

                    // Next
                    Button {
                        if let nextSong = queueManager.next() {
                            Task {
                                await audioEngine.prepareNext(song: nextSong)
                                audioEngine.beginCrossfade(to: nextSong)
                            }
                        }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .disabled(!queueManager.hasNext)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
            .padding(.horizontal, 8)
            .onTapGesture {
                showNowPlaying = true
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
