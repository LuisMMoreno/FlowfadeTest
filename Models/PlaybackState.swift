import Foundation
import SwiftData

@Model
final class PlaybackState {
    @Attribute(.unique) var id: UUID
    var currentSongID: UUID?
    var currentTime: TimeInterval
    var queueSongIDs: [UUID]
    var queueIndex: Int
    var isShuffleOn: Bool
    var crossfadeDuration: TimeInterval
    var isCrossfadeEnabled: Bool

    init(
        id: UUID = UUID(),
        currentSongID: UUID? = nil,
        currentTime: TimeInterval = 0,
        queueSongIDs: [UUID] = [],
        queueIndex: Int = 0,
        isShuffleOn: Bool = false,
        crossfadeDuration: TimeInterval = 6.0,
        isCrossfadeEnabled: Bool = true
    ) {
        self.id = id
        self.currentSongID = currentSongID
        self.currentTime = currentTime
        self.queueSongIDs = queueSongIDs
        self.queueIndex = queueIndex
        self.isShuffleOn = isShuffleOn
        self.crossfadeDuration = crossfadeDuration
        self.isCrossfadeEnabled = isCrossfadeEnabled
    }
}
