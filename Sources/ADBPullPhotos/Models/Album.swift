import Foundation

struct Album: Identifiable, Hashable {
    let id: String
    var name: String
    var remotePath: String
    var localPath: String
    var enabled: Bool
    var scanState: ScanState = .idle
    var mediaCount: Int?

    var displayCount: String {
        if let mediaCount {
            "\(mediaCount)"
        } else {
            ""
        }
    }
}

enum ScanState: Hashable {
    case idle
    case scanning
    case loaded
    case failed(String)
}
