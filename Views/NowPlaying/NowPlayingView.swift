import SwiftUI

/// Full-screen Now Playing view with artwork, controls, and progress bar.
struct NowPlayingView: View {

    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = NowPlayingViewModel()
    @State private var showQueue = false
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // Background blur effect from artwork
                backgroundView

                VStack(spacing: 0) {
                    // Drag indicator
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12)

                    Spacer()

                    // Artwork
                    artworkSection
                        .padding(.horizontal, 40)

                    Spacer()
                        .frame(height: 32)

                    // Song info
                    songInfoSection

                    Spacer()
                        .frame(height: 28)

                    // Progress bar
                    progressSection
                        .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 24)

                    // Playback controls
                    controlsSection

                    Spacer()
                        .frame(height: 24)

                    // Bottom bar (shuffle, queue)
                    bottomBarSection
                        .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 20)
                }
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            if let data = audioEngine.currentSong?.artworkData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60)
                    .scaleEffect(1.3)
            } else {
                LinearGradient(
                    colors: [
                        Color(hue: 0.75, saturation: 0.5, brightness: 0.2),
                        Color(hue: 0.6, saturation: 0.4, brightness: 0.1),
                        .black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Darken overlay
            Color.black.opacity(0.4)
        }
        .ignoresSafeArea()
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        ArtworkView(
            artworkData: audioEngine.currentSong?.artworkData,
            size: UIScreen.main.bounds.width - 80
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .animation(.spring(duration: 0.6), value: audioEngine.currentSong?.id)
    }

    // MARK: - Song Info

    private var songInfoSection: some View {
        VStack(spacing: 6) {
            Text(audioEngine.currentSong?.displayTitle ?? "Not Playing")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(audioEngine.currentSong?.displayArtist ?? "")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            if audioEngine.isCrossfading {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Crossfading")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut, value: audioEngine.isCrossfading)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isDragging ? dragValue : audioEngine.currentTime },
                    set: { newValue in
                        dragValue = newValue
                        isDragging = true
                    }
                ),
                in: 0...max(audioEngine.duration, 1)
            ) { editing in
                if !editing {
                    isDragging = false
                    viewModel.seek(to: dragValue, audioEngine: audioEngine)
                }
            }
            .tint(.white)

            HStack {
                Text(NowPlayingViewModel.formatTime(isDragging ? dragValue : audioEngine.currentTime))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()

                Spacer()

                Text("-" + NowPlayingViewModel.formatTime(max(0, audioEngine.duration - (isDragging ? dragValue : audioEngine.currentTime))))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 48) {
            // Previous
            Button {
                viewModel.skipPrevious(audioEngine: audioEngine, queueManager: queueManager)
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!queueManager.hasPrevious && audioEngine.currentTime <= 3)

            // Play / Pause
            Button {
                viewModel.togglePlayPause(audioEngine: audioEngine)
            } label: {
                Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: audioEngine.isPlaying)
            }

            // Next
            Button {
                viewModel.skipNext(audioEngine: audioEngine, queueManager: queueManager)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!queueManager.hasNext)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBarSection: some View {
        HStack {
            // Shuffle button
            Button {
                viewModel.toggleShuffle(queueManager: queueManager)
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(queueManager.isShuffleOn ? .green : .white.opacity(0.5))
            }

            Spacer()

            // Queue button
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
