import SwiftUI
import SwiftData

@main
struct FlowfadeApp: App {
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var queueManager = QueueManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Song.self,
            Playlist.self,
            PlaybackState.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioEngine)
                .environmentObject(queueManager)
                .onAppear {
                    configureAudioSession()
                    restorePlaybackState()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    savePlaybackState()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func restorePlaybackState() {
        // Restoration is handled by NowPlayingViewModel on first load
    }

    private func savePlaybackState() {
        audioEngine.saveCurrentState()
    }
}

import AVFoundation
