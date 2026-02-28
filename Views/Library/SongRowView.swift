import SwiftUI

/// A single song row in the library or playlist list.
struct SongRowView: View {

    let song: Song
    let isCurrentlyPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artworkData: song.artworkData, size: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayTitle)
                    .font(.body)
                    .fontWeight(isCurrentlyPlaying ? .semibold : .regular)
                    .foregroundStyle(isCurrentlyPlaying ? Color.accentColor : .primary)
                    .lineLimit(1)

                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(NowPlayingViewModel.formatTime(song.duration))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            if isCurrentlyPlaying {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.accent)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
        }
        .contentShape(Rectangle())
    }
}
