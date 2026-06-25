import SwiftUI

struct AlbumSidebar: View {
    @EnvironmentObject private var viewModel: LibraryViewModel

    var body: some View {
        List(selection: $viewModel.selectedAlbumID) {
            Section(L.albums) {
                ForEach(viewModel.albums) { album in
                    AlbumRow(album: album)
                        .tag(album.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await viewModel.selectAlbum(album) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(L.appTitle)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L.currentAlbumOnly, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

private struct AlbumRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.body)
                    .lineLimit(1)

                Text(album.remotePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            statusView
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch album.scanState {
        case .scanning:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        default:
            if !album.displayCount.isEmpty {
                Text(album.displayCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        if album.id.lowercased().contains("screenshot") {
            return "rectangle.dashed"
        }
        return "photo.on.rectangle"
    }
}
