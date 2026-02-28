import Foundation
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

/// Service responsible for importing audio files into the app's sandbox.
/// Handles file copy, hash generation, deduplication, and metadata extraction.
class FileImportService {

    /// Supported UTTypes for the file picker
    static let supportedContentTypes: [UTType] = [
        .mp3,
        .mpeg4Audio,
        .wav,
        .flac,
        .aiff,
        .audio
    ]

    /// Music directory inside the app's Documents folder
    private static var musicDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let musicDir = docs.appendingPathComponent(Constants.musicDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        return musicDir
    }

    /// Import a single audio file into the app sandbox.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the file to import (from document picker)
    ///   - modelContext: SwiftData model context for saving
    /// - Returns: The created Song, or nil if import failed or file already exists
    static func importFile(from sourceURL: URL, modelContext: ModelContext) async -> Song? {
        // Start accessing security-scoped resource
        guard sourceURL.startAccessingSecurityScopedResource() else {
            print("Cannot access security-scoped resource: \(sourceURL)")
            return nil
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        // Check if file extension is supported
        let ext = sourceURL.pathExtension.lowercased()
        guard Constants.supportedExtensions.contains(ext) else {
            print("Unsupported file extension: \(ext)")
            return nil
        }

        // Generate hash for deduplication
        guard let fileHash = FileHasher.hash(fileAt: sourceURL) else {
            print("Could not hash file: \(sourceURL)")
            return nil
        }

        // Check if song already imported
        let existingPredicate = #Predicate<Song> { song in
            song.fileHash == fileHash
        }
        let existingDescriptor = FetchDescriptor<Song>(predicate: existingPredicate)
        if let existingCount = try? modelContext.fetchCount(existingDescriptor), existingCount > 0 {
            print("Song already imported (hash: \(fileHash))")
            return nil
        }

        // Copy file to sandbox
        let fileName = sourceURL.lastPathComponent
        let destinationURL = musicDirectory.appendingPathComponent(fileName)

        // Handle filename conflicts
        let finalURL = uniqueFileURL(for: destinationURL)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: finalURL)
        } catch {
            print("Failed to copy file: \(error)")
            return nil
        }

        // Extract metadata
        let metadata = await MetadataService.extractMetadata(from: finalURL)

        // Create relative path for storage
        let relativePath = "\(Constants.musicDirectoryName)/\(finalURL.lastPathComponent)"

        // Create Song model
        let song = Song(
            fileHash: fileHash,
            fileName: fileName,
            filePath: relativePath,
            title: metadata.title,
            artist: metadata.artist,
            artworkData: metadata.artworkData,
            duration: metadata.duration
        )

        modelContext.insert(song)

        do {
            try modelContext.save()
        } catch {
            print("Failed to save song: \(error)")
            // Clean up copied file
            try? FileManager.default.removeItem(at: finalURL)
            return nil
        }

        return song
    }

    /// Import multiple files at once
    static func importFiles(from urls: [URL], modelContext: ModelContext) async -> [Song] {
        var imported: [Song] = []
        for url in urls {
            if let song = await importFile(from: url, modelContext: modelContext) {
                imported.append(song)
            }
        }
        return imported
    }

    /// Delete a song's file from the sandbox
    static func deleteFile(for song: Song) {
        let fileURL = song.fileURL
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    /// Generate a unique filename if a file with the same name already exists
    private static func uniqueFileURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newURL: URL

        repeat {
            let newName = "\(baseName)_\(counter).\(ext)"
            newURL = directory.appendingPathComponent(newName)
            counter += 1
        } while fileManager.fileExists(atPath: newURL.path)

        return newURL
    }
}
