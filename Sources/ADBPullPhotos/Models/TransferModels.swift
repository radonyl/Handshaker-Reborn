import Foundation

struct TransferSummary: Equatable {
    var total: Int = 0
    var completed: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var currentFilename: String?

    var isComplete: Bool {
        total > 0 && completed + skipped + failed >= total
    }
}

enum TransferState: Equatable {
    case idle
    case choosingDestination
    case running(TransferSummary)
    case finished(TransferSummary, URL)
    case failed(String)

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}
