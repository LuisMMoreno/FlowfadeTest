import SwiftUI

/// Displays song artwork with a fallback gradient when no artwork is available.
struct ArtworkView: View {

    let artworkData: Data?
    let size: CGFloat

    init(artworkData: Data?, size: CGFloat = 60) {
        self.artworkData = artworkData
        self.size = size
    }

    var body: some View {
        Group {
            if let data = artworkData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback: gradient with music note
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: 0.75, saturation: 0.4, brightness: 0.3),
                            Color(hue: 0.6, saturation: 0.5, brightness: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 100 ? 16 : 8))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

#Preview {
    HStack(spacing: 20) {
        ArtworkView(artworkData: nil, size: 50)
        ArtworkView(artworkData: nil, size: 100)
        ArtworkView(artworkData: nil, size: 200)
    }
    .padding()
    .background(.black)
}
