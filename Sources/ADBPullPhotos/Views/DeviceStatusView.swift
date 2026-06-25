import SwiftUI

struct DeviceStatusView: View {
    let status: DeviceStatus

    var body: some View {
        Label {
            Text(status.message)
                .font(.subheadline)
                .lineLimit(1)
        } icon: {
            Image(systemName: status.tone.systemImage)
                .symbolRenderingMode(.palette)
                .foregroundStyle(primaryColor, secondaryColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel(status.message)
    }

    private var primaryColor: Color {
        switch status.tone {
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    private var secondaryColor: Color {
        .secondary
    }
}
