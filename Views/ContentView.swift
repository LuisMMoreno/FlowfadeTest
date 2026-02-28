import SwiftUI
import SwiftData

/// Root view with TabView and persistent MiniPlayer overlay.
struct ContentView: View {

    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var queueManager: QueueManager
    @Environment(\.modelContext) private var modelContext

    @State private var showNowPlaying = false
    @StateObject private var nowPlayingVM = NowPlayingViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "music.note.house.fill")
                    }

                PlaylistListView()
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .tint(.purple)

            // Mini player overlay (above tab bar)
            VStack {
                Spacer()
                MiniPlayerView(showNowPlaying: $showNowPlaying)
                    .padding(.bottom, 49) // Height of tab bar
            }
            .animation(.spring(duration: 0.4), value: audioEngine.currentSong?.id)
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .onAppear {
            // Restore playback state
            nowPlayingVM.restoreState(
                modelContext: modelContext,
                audioEngine: audioEngine,
                queueManager: queueManager
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            nowPlayingVM.saveState(
                modelContext: modelContext,
                audioEngine: audioEngine,
                queueManager: queueManager
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioEngine.shared)
        .environmentObject(QueueManager.shared)
}
