import SwiftUI
import SwiftData
import PhotosUI

/// Sheet for editing a song's metadata.
/// Only appears when the user explicitly requests it.
/// Saves to SwiftData ONLY — never modifies the original file.
struct MetadataEditorSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = MetadataEditorViewModel()

    let song: Song

    var body: some View {
        NavigationStack {
            Form {
                // Artwork Section
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ArtworkView(artworkData: viewModel.artworkData, size: 150)

                            HStack(spacing: 16) {
                                PhotosPicker(
                                    selection: $viewModel.selectedPhotoItem,
                                    matching: .images
                                ) {
                                    Label("Choose", systemImage: "photo.on.rectangle")
                                        .font(.caption)
                                }

                                if viewModel.artworkData != nil {
                                    Button(role: .destructive) {
                                        viewModel.removeArtwork()
                                    } label: {
                                        Label("Remove", systemImage: "xmark.circle")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Artwork")
                }

                // Metadata Fields
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Song Title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Song title", text: $viewModel.title)
                            .textFieldStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Artist name", text: $viewModel.artist)
                            .textFieldStyle(.plain)
                    }
                } header: {
                    Text("Info")
                }

                // File Info (read-only)
                Section {
                    LabeledContent("File", value: song.fileName)
                    LabeledContent("Duration", value: NowPlayingViewModel.formatTime(song.duration))
                } header: {
                    Text("File Details")
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.save(modelContext: modelContext)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: viewModel.selectedPhotoItem) { _, _ in
                Task {
                    await viewModel.handlePhotoSelection()
                }
            }
        }
        .onAppear {
            viewModel.load(song: song)
        }
    }
}
