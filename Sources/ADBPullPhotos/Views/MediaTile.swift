import AppKit
import SwiftUI

struct MediaTile: View {
    let media: RemoteMedia
    let isSelected: Bool
    private let thumbnailSize: CGFloat = 82

    var body: some View {
        VStack(alignment: .center, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                if media.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(5)
                }

                if isSelected {
                    selectionMark
                        .padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.14), lineWidth: isSelected ? 2 : 1)
            }

            Text(media.filename)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: 116, alignment: .top)
                .frame(minHeight: 34, alignment: .top)
        }
        .frame(width: 116, height: 132, alignment: .top)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailURL = media.thumbnailURL {
            ThumbnailFileImage(url: thumbnailURL, fallbackSymbolName: media.mediaType.symbolName)
        } else {
            ThumbnailPlaceholder(symbolName: media.mediaType.symbolName)
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .shadow(radius: 2, y: 1)
        }
    }
}

private struct ThumbnailFileImage: View {
    let url: URL
    let fallbackSymbolName: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ThumbnailPlaceholder(symbolName: fallbackSymbolName)
            }
        }
        .task(id: url) {
            image = nil
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value

            guard let data, let decoded = NSImage(data: data) else {
                return
            }

            image = decoded
        }
    }
}

private struct ThumbnailPlaceholder: View {
    let symbolName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)

            Image(systemName: symbolName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
