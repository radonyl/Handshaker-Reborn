import SwiftUI

struct TransferBar: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                Label(L.selectedCount(viewModel.selectedMediaIDs.count), systemImage: "checkmark.circle")
                    .foregroundStyle(viewModel.selectedMediaIDs.isEmpty ? .secondary : .primary)

                transferStatus

                Spacer()

                if case .finished = viewModel.transferState {
                    Button {
                        viewModel.openTransferredFolder()
                    } label: {
                        Label(L.showInFinder, systemImage: "folder")
                    }
                }

                Button {
                    viewModel.chooseDestinationAndTransfer()
                } label: {
                    Label(buttonTitle, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canTransfer)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var transferStatus: some View {
        switch viewModel.transferState {
        case .idle:
            Text(L.selectFilesToTransfer)
                .foregroundStyle(.secondary)
        case .choosingDestination:
            Text(L.choosingDestination)
                .foregroundStyle(.secondary)
        case .running(let summary):
            HStack(spacing: 8) {
                ProgressView(value: Double(summary.completed + summary.skipped + summary.failed), total: Double(max(summary.total, 1)))
                    .frame(width: 160)
                Text(summary.currentFilename ?? L.preparingTransfer)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        case .finished(let summary, _):
            Text(L.completedSummary(completed: summary.completed, failed: summary.failed))
                .foregroundStyle(summary.failed == 0 ? Color.secondary : Color.orange)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private var buttonTitle: String {
        if viewModel.transferState.isRunning {
            return L.transferRunning
        }
        return L.transfer
    }
}
