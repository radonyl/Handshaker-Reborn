import SwiftUI

@main
struct ADBPullPhotosApp: App {
    @StateObject private var viewModel = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    await viewModel.refreshDeviceAndAlbums()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L.refreshDevice) {
                    Task { await viewModel.refreshDeviceAndAlbums() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(L.selectAllCurrentAlbum) {
                    viewModel.selectAllVisible()
                }
                .keyboardShortcut("a", modifiers: [.command])
                .disabled(viewModel.visibleMedia.isEmpty)
            }
        }
    }
}
