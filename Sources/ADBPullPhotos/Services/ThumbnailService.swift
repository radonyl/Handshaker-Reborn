import AppKit
import AVFoundation
import Foundation
import QuickLookThumbnailing

struct ThumbnailService {
    func thumbnailURL(for media: RemoteMedia, sourceURL: URL) async throws -> URL {
        try FileManager.default.createDirectory(
            at: AppPaths.thumbnailCacheURL,
            withIntermediateDirectories: true
        )

        let thumbnailURL = AppPaths.thumbnailCacheURL
            .appendingPathComponent(ADBService.cacheKey(for: media.remotePath))
            .appendingPathExtension("jpg")

        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            return thumbnailURL
        }

        let image: NSImage
        switch media.mediaType {
        case .image:
            image = try await quickLookThumbnail(for: sourceURL) ?? loadImageThumbnail(from: sourceURL)
        case .video:
            if let videoImage = try await videoThumbnail(from: sourceURL) {
                image = videoImage
            } else if let quickLookImage = try await quickLookThumbnail(for: sourceURL) {
                image = quickLookImage
            } else {
                image = placeholder(for: media)
            }
        }

        guard let data = image.jpegData(maxDimension: 420) else {
            throw ADBError.commandFailed(L.thumbnailGenerationFailed(media.filename))
        }

        try data.write(to: thumbnailURL, options: .atomic)
        return thumbnailURL
    }

    private func quickLookThumbnail(for url: URL) async throws -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 420, height: 420),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        return try await withCheckedThrowingContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    private func videoThumbnail(from url: URL) async throws -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 420, height: 420)

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 1, preferredTimescale: 600))]) { _, image, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: NSImage(cgImage: image, size: .zero))
            }
        }
    }

    private func loadImageThumbnail(from url: URL) -> NSImage {
        if let image = NSImage(contentsOf: url) {
            return image
        }
        return placeholder(systemName: "photo")
    }

    private func placeholder(for media: RemoteMedia) -> NSImage {
        placeholder(systemName: media.mediaType.symbolName)
    }

    private func placeholder(systemName: String) -> NSImage {
        let image = NSImage(size: CGSize(width: 420, height: 420))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 420, height: 420)).fill()

        let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) ?? NSImage()
        symbol.draw(
            in: NSRect(x: 150, y: 150, width: 120, height: 120),
            from: .zero,
            operation: .sourceOver,
            fraction: 0.65
        )

        image.unlockFocus()
        return image
    }
}

private extension NSImage {
    func jpegData(maxDimension: CGFloat) -> Data? {
        let scale = min(maxDimension / max(size.width, size.height), 1)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let output = NSImage(size: targetSize)

        output.lockFocus()
        draw(in: CGRect(origin: .zero, size: targetSize))
        output.unlockFocus()

        guard
            let tiff = output.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
