import Foundation
import SwiftUI
import SwiftData
import PhotosUI

/// ViewModel for the metadata editor sheet.
/// Edits metadata in SwiftData only — NEVER modifies the original audio file.
@MainActor
final class MetadataEditorViewModel: ObservableObject {

    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var artworkData: Data?
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var isSaving: Bool = false

    private var song: Song?

    // MARK: - Setup

    func load(song: Song) {
        self.song = song
        self.title = song.title
        self.artist = song.artist
        self.artworkData = song.artworkData
    }

    // MARK: - Save

    func save(modelContext: ModelContext) {
        guard let song = song else { return }

        isSaving = true

        song.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        song.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        if let newArtwork = artworkData {
            song.artworkData = newArtwork
        }

        song.isMetadataEdited = true

        try? modelContext.save()

        isSaving = false
    }

    // MARK: - Artwork Selection

    func handlePhotoSelection() async {
        guard let item = selectedPhotoItem else { return }

        if let data = try? await item.loadTransferable(type: Data.self) {
            artworkData = data
        }
    }

    func removeArtwork() {
        artworkData = nil
    }
}
