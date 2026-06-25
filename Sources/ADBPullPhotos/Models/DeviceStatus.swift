import Foundation

struct DeviceStatus: Equatable {
    var adbAvailable: Bool
    var connected: Bool
    var authorized: Bool
    var deviceID: String?
    var message: String
    var detail: String?

    static let checking = DeviceStatus(
        adbAvailable: true,
        connected: false,
        authorized: false,
        deviceID: nil,
        message: L.checkingDevice,
        detail: nil
    )

    var tone: StatusTone {
        if connected && authorized { return .success }
        if adbAvailable { return .warning }
        return .error
    }
}

enum StatusTone {
    case success
    case warning
    case error

    var systemImage: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }
}
