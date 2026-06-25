import Foundation

struct RemoteMedia: Identifiable, Hashable {
    let id: String
    var remotePath: String
    var filename: String
    var mediaType: MediaType
    var size: Int64?
    var modifiedAt: Date?
    var albumID: String
    var transferred: Bool
    var thumbnailURL: URL?

    var fileExtension: String {
        URL(fileURLWithPath: filename).pathExtension.uppercased()
    }

    var sizeLabel: String {
        guard let size else { return L.unknownSize }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum MediaType: String, Hashable {
    case image
    case video

    var label: String {
        switch self {
        case .image:
            L.image
        case .video:
            L.video
        }
    }

    var symbolName: String {
        switch self {
        case .image:
            "photo"
        case .video:
            "play.rectangle.fill"
        }
    }

    static func infer(from filename: String) -> MediaType? {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if Self.imageExtensions.contains(ext) {
            return .image
        }
        if Self.videoExtensions.contains(ext) {
            return .video
        }
        return nil
    }

    private static let imageExtensions = [
        "jpg", "jpeg", "png", "webp", "heic", "gif"
    ]

    private static let videoExtensions = [
        "mp4", "mov", "mkv", "3gp", "webm"
    ]
}
