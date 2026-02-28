import Foundation
import SwiftData

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var dateCreated: Date
    var songIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        dateCreated: Date = Date(),
        songIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.songIDs = songIDs
    }

    var songCount: Int {
        songIDs.count
    }
}
