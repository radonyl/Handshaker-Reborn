import SwiftUI

struct MediaBrowser: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 132), spacing: 22)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content

            TransferBar()
        }
        .navigationTitle(viewModel.selectedAlbum?.name ?? L.media)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.selectedAlbum?.name ?? L.chooseAlbum)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(viewModel.selectedAlbum?.remotePath ?? L.chooseAlbumFromSidebar)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let selectedAlbum = viewModel.selectedAlbum, !viewModel.visibleMedia.isEmpty {
                    Text(loadedCountText(for: selectedAlbum))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                viewModel.selectAllVisible()
            } label: {
                Label(L.selectAllLoaded, systemImage: "checkmark.circle")
            }
            .disabled(viewModel.visibleMedia.isEmpty)

            Button {
                viewModel.clearSelection()
            } label: {
                Label(L.clearSelection, systemImage: "xmark.circle")
            }
            .disabled(viewModel.selectedMediaIDs.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func loadedCountText(for album: Album) -> String {
        if let mediaCount = album.mediaCount {
            return L.loadedCount(viewModel.visibleMedia.count, total: mediaCount)
        }

        if viewModel.hasMoreMedia {
            return L.loadedMoreAvailable(viewModel.visibleMedia.count)
        }

        return L.loadedCount(viewModel.visibleMedia.count)
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.deviceStatus.connected || !viewModel.deviceStatus.authorized {
            ContentUnavailableView {
                Label(viewModel.deviceStatus.message, systemImage: "cable.connector")
            } description: {
                Text(viewModel.deviceStatus.detail ?? L.connectionFallback)
            } actions: {
                Button(L.refreshDevice) {
                    Task { await viewModel.refreshDeviceAndAlbums() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isScanningAlbums {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(L.scanningPhoneAlbums)
                    .font(.headline)
                Text(L.scanningPhoneAlbumsDetail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedAlbum == nil {
            ContentUnavailableView(L.chooseAlbum, systemImage: "sidebar.left", description: Text(L.chooseAlbumDescription))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedAlbum?.scanState == .scanning {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(L.scanningAlbum)
                    .font(.headline)
                Text(L.scanningAlbumDetail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let message) = viewModel.selectedAlbum?.scanState {
            ContentUnavailableView {
                Label(L.scanFailed, systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(L.retry) {
                    if let album = viewModel.selectedAlbum {
                        Task { await viewModel.selectAlbum(album) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visibleMedia.isEmpty {
            ContentUnavailableView(L.noMedia, systemImage: "photo.stack", description: Text(L.noMediaDescription))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.visibleMedia) { media in
                        MediaTile(
                            media: media,
                            isSelected: viewModel.selectedMediaIDs.contains(media.id)
                        )
                        .onTapGesture {
                            viewModel.handleSelection(of: media, modifiers: NSEvent.modifierFlags)
                        }
                        .task {
                            await viewModel.loadThumbnailIfNeeded(for: media)
                        }
                        .onAppear {
                            Task {
                                await viewModel.loadNextMediaPageIfNeeded(current: media)
                            }
                        }
                    }

                    if viewModel.isLoadingMediaPage {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 116, height: 116)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
