import Foundation
import SwiftData

@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var fileHash: String
    var fileName: String
    var filePath: String
    var title: String
    var artist: String
    @Attribute(.externalStorage) var artworkData: Data?
    var duration: TimeInterval
    var dateAdded: Date
    var isMetadataEdited: Bool

    init(
        id: UUID = UUID(),
        fileHash: String,
        fileName: String,
        filePath: String,
        title: String,
        artist: String,
        artworkData: Data? = nil,
        duration: TimeInterval = 0,
        dateAdded: Date = Date(),
        isMetadataEdited: Bool = false
    ) {
        self.id = id
        self.fileHash = fileHash
        self.fileName = fileName
        self.filePath = filePath
        self.title = title
        self.artist = artist
        self.artworkData = artworkData
        self.duration = duration
        self.dateAdded = dateAdded
        self.isMetadataEdited = isMetadataEdited
    }

    /// Full URL to the audio file in the app's sandbox
    var fileURL: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent(filePath)
    }

    /// Display title — always returns something meaningful
    var displayTitle: String {
        title.isEmpty ? fileName : title
    }

    /// Display artist — fallback to "Unknown Artist"
    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }
}
