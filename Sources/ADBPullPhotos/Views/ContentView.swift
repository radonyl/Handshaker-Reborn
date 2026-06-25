import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        NavigationSplitView {
            AlbumSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            MediaBrowser()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                DeviceStatusView(status: viewModel.deviceStatus)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refreshDeviceAndAlbums() }
                } label: {
                    Label(L.refresh, systemImage: "arrow.clockwise")
                }
                .help(L.refreshDeviceHelp)

                Button {
                    viewModel.chooseDestinationAndTransfer()
                } label: {
                    Label(L.transfer, systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canTransfer)
                .help(L.transferSelectedHelp)
            }
        }
        .alert(
            L.alertTitle,
            isPresented: Binding(
                get: { viewModel.bannerMessage != nil },
                set: { if !$0 { viewModel.bannerMessage = nil } }
            )
        ) {
            Button(L.ok) { viewModel.bannerMessage = nil }
        } message: {
            Text(viewModel.bannerMessage ?? "")
        }
    }
}
