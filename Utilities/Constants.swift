import Foundation

enum Constants {
    /// Directory name for imported music files within Documents
    static let musicDirectoryName = "Music"

    /// Default crossfade duration in seconds
    static let defaultCrossfadeDuration: TimeInterval = 6.0

    /// Minimum crossfade duration
    static let minCrossfadeDuration: TimeInterval = 1.0

    /// Maximum crossfade duration
    static let maxCrossfadeDuration: TimeInterval = 12.0

    /// Number of bytes to read for file hashing (64KB)
    static let hashByteCount = 64 * 1024

    /// RMS analysis window size in seconds
    static let rmsWindowSize: TimeInterval = 1.0

    /// Number of seconds from end of song to analyze for adaptive crossfade
    static let crossfadeAnalysisWindow: TimeInterval = 10.0

    /// RMS threshold below which a song is considered to be fading out naturally
    static let naturalFadeThreshold: Float = 0.05

    /// Minimum crossfade multiplier (for songs that fade naturally)
    static let minCrossfadeMultiplier: Double = 0.5

    /// Volume update interval for crossfade (approx 60fps)
    static let crossfadeTimerInterval: TimeInterval = 1.0 / 60.0

    /// Number of recent songs to exclude in shuffle
    static let shuffleHistoryDepthFraction = 3 // songCount / this value

    /// Max recent songs to track for shuffle
    static let shuffleMaxHistory = 10

    /// Number of recent artists to penalize in shuffle
    static let shuffleArtistPenaltyDepth = 3

    /// Supported audio file extensions
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aac", "caf", "aiff"]

    /// Playback state save key
    static let playbackStateID = "flowfade_playback_state"
}
