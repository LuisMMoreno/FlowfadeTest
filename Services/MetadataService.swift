import Foundation
import AVFoundation

/// Service to read metadata from audio files using AVFoundation.
/// Falls back to filename parsing when metadata is missing.
struct MetadataService {

    struct SongMetadata {
        var title: String
        var artist: String
        var artworkData: Data?
        var duration: TimeInterval
    }

    // MARK: - Public API

    /// Extract metadata from an audio file URL.
    /// Tries AVAsset metadata first, then falls back to filename parsing.
    static func extractMetadata(from url: URL) async -> SongMetadata {
        let asset = AVURLAsset(url: url)

        // Get duration
        let duration = await loadDuration(from: asset)

        // Try reading embedded metadata
        let embeddedTitle = await loadMetadataValue(from: asset, key: .commonKeyTitle)
        let embeddedArtist = await loadMetadataValue(from: asset, key: .commonKeyArtist)
        let embeddedArtwork = await loadArtwork(from: asset)

        // If we got at least a title from metadata, use it
        if let title = embeddedTitle, !title.isEmpty {
            return SongMetadata(
                title: title,
                artist: embeddedArtist ?? "Unknown Artist",
                artworkData: embeddedArtwork,
                duration: duration
            )
        }

        // Fallback: parse from filename
        let parsed = parseFilename(url.deletingPathExtension().lastPathComponent)
        return SongMetadata(
            title: parsed.title,
            artist: parsed.artist,
            artworkData: embeddedArtwork, // might still have artwork even without title tag
            duration: duration
        )
    }

    // MARK: - AVAsset Metadata Reading

    private static func loadDuration(from asset: AVURLAsset) async -> TimeInterval {
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            print("Could not load duration: \(error)")
            return 0
        }
    }

    private static func loadMetadataValue(
        from asset: AVURLAsset,
        key: AVMetadataKey
    ) async -> String? {
        do {
            let metadata = try await asset.load(.commonMetadata)
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: AVMetadataIdentifier.commonIdentifier(for: key)
            )
            if let item = items.first {
                let value = try await item.load(.stringValue)
                return value
            }
        } catch {
            print("Could not load metadata for key \(key): \(error)")
        }
        return nil
    }

    private static func loadArtwork(from asset: AVURLAsset) async -> Data? {
        do {
            let metadata = try await asset.load(.commonMetadata)
            let artworkItems = AVMetadataItem.metadataItems(
                from: metadata,
                filteredByIdentifier: .commonIdentifierArtwork
            )
            if let item = artworkItems.first {
                let data = try await item.load(.dataValue)
                return data
            }
        } catch {
            print("Could not load artwork: \(error)")
        }
        return nil
    }

    // MARK: - Filename Parsing

    /// Parse artist and title from a filename.
    ///
    /// Strategy:
    /// 1. Replace `-` and `_` with spaces
    /// 2. Look for a separator pattern like " - " to split artist/title
    /// 3. If no separator found, use the whole name as title
    ///
    /// Examples:
    /// - "pepito-la-toalla-mojada-letra" → artist: "pepito", title: "la toalla mojada letra"
    /// - "Song Name" → artist: "Unknown Artist", title: "Song Name"
    /// - "Artist - Song Title" → artist: "Artist", title: "Song Title"
    static func parseFilename(_ filename: String) -> (title: String, artist: String) {
        let cleaned = filename
            .replacingOccurrences(of: "_", with: " ")

        // Try splitting on " - " first (common format: "Artist - Title")
        if cleaned.contains(" - ") {
            let parts = cleaned.components(separatedBy: " - ")
            if parts.count >= 2 {
                let artist = parts[0].trimmingCharacters(in: .whitespaces)
                let title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                return (title: title, artist: artist)
            }
        }

        // Try splitting on the first hyphen with surrounding context
        // e.g., "pepito-la-toalla-mojada-letra"
        let hyphenParts = cleaned.components(separatedBy: "-")
        if hyphenParts.count >= 2 {
            let artist = hyphenParts[0].trimmingCharacters(in: .whitespaces)
            let title = hyphenParts.dropFirst()
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty && !title.isEmpty {
                return (title: title, artist: artist)
            }
        }

        // No separator found — use entire name as title
        return (title: cleaned.trimmingCharacters(in: .whitespaces), artist: "Unknown Artist")
    }

    // MARK: - AVMetadataKey helper

}

// MARK: - AVMetadataIdentifier convenience

private extension AVMetadataIdentifier {
    static func commonIdentifier(for key: AVMetadataKey) -> AVMetadataIdentifier {
        switch key {
        case .commonKeyTitle:
            return .commonIdentifierTitle
        case .commonKeyArtist:
            return .commonIdentifierArtist
        default:
            return .commonIdentifierTitle
        }
    }
}
