import AppKit
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var deviceStatus: DeviceStatus = .checking
    @Published var albums: [Album] = []
    @Published var selectedAlbumID: Album.ID?
    @Published var visibleMedia: [RemoteMedia] = []
    @Published var selectedMediaIDs: Set<RemoteMedia.ID> = []
    @Published var transferState: TransferState = .idle
    @Published var bannerMessage: String?
    @Published var isScanningAlbums = false
    @Published var isLoadingMediaPage = false
    @Published var hasMoreMedia = false

    private let adbService = ADBService()
    private let thumbnailService = ThumbnailService()
    private var configDeviceID: String?
    private var thumbnailLoads: Set<RemoteMedia.ID> = []
    private var thumbnailQueued: Set<RemoteMedia.ID> = []
    private var thumbnailQueue: [RemoteMedia] = []
    private var activeThumbnailLoadCount = 0
    private let maxConcurrentThumbnailLoads = 2
    private var lastSelectedMediaID: RemoteMedia.ID?
    private let mediaPageSize = 80

    var selectedAlbum: Album? {
        guard let selectedAlbumID else { return nil }
        return albums.first { $0.id == selectedAlbumID }
    }

    var selectedMedia: [RemoteMedia] {
        visibleMedia.filter { selectedMediaIDs.contains($0.id) }
    }

    var canTransfer: Bool {
        deviceStatus.connected &&
        deviceStatus.authorized &&
        !selectedMediaIDs.isEmpty &&
        !transferState.isRunning
    }

    func refreshDevice() async {
        deviceStatus = .checking
        deviceStatus = await adbService.deviceStatus(configDeviceID: configDeviceID)
    }

    func refreshDeviceAndAlbums() async {
        await refreshDevice()
        await loadAlbums()
    }

    func loadAlbums() async {
        isScanningAlbums = true
        defer { isScanningAlbums = false }

        do {
            let configuration = try ConfigStore.load()
            configDeviceID = configuration.deviceID
        } catch {
            configDeviceID = nil
        }

        guard deviceStatus.connected, deviceStatus.authorized else {
            albums = []
            selectedAlbumID = nil
            visibleMedia = []
            selectedMediaIDs = []
            hasMoreMedia = false
            return
        }

        do {
            let scannedAlbums = try await adbService.scanAlbums(deviceID: deviceStatus.deviceID)
            albums = scannedAlbums

            if selectedAlbumID == nil {
                selectedAlbumID = albums.first?.id
            } else if !albums.contains(where: { $0.id == selectedAlbumID }) {
                selectedAlbumID = albums.first?.id
            }

            if let selectedAlbum {
                await selectAlbum(selectedAlbum)
            }
        } catch {
            albums = []
            visibleMedia = []
            selectedMediaIDs = []
            hasMoreMedia = false
            bannerMessage = L.unableToScanAlbums(error.localizedDescription)
        }
    }

    func selectAlbum(_ album: Album) async {
        guard !transferState.isRunning else { return }
        selectedAlbumID = album.id
        selectedMediaIDs = []
        lastSelectedMediaID = nil
        visibleMedia = []
        hasMoreMedia = true
        resetThumbnailQueue()

        updateAlbum(album.id) { $0.scanState = .scanning }

        guard deviceStatus.connected, deviceStatus.authorized else {
            updateAlbum(album.id) { $0.scanState = .idle }
            return
        }

        await loadNextMediaPage(reset: true)
    }

    func loadNextMediaPageIfNeeded(current media: RemoteMedia) async {
        guard hasMoreMedia, !isLoadingMediaPage else { return }
        guard let index = visibleMedia.firstIndex(where: { $0.id == media.id }) else { return }

        let thresholdIndex = max(visibleMedia.count - 32, 0)
        if index >= thresholdIndex {
            await loadNextMediaPage(reset: false)
        }
    }

    func loadNextMediaPage(reset: Bool) async {
        guard let selectedAlbum else { return }
        guard !isLoadingMediaPage else { return }
        guard hasMoreMedia || reset else { return }

        isLoadingMediaPage = true
        defer { isLoadingMediaPage = false }

        let offset = reset ? 0 : visibleMedia.count

        do {
            let page = try await adbService.listMedia(
                in: selectedAlbum,
                deviceID: deviceStatus.deviceID,
                offset: offset,
                limit: mediaPageSize
            )

            if reset {
                visibleMedia = page
            } else {
                visibleMedia.append(contentsOf: page)
            }

            hasMoreMedia = page.count == mediaPageSize
            updateAlbum(selectedAlbum.id) { $0.scanState = .loaded }
        } catch {
            if reset {
                visibleMedia = []
            }
            hasMoreMedia = false
            updateAlbum(selectedAlbum.id) {
                $0.scanState = .failed(error.localizedDescription)
            }
        }
    }

    func handleSelection(of media: RemoteMedia, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let lastSelectedMediaID {
            selectRange(from: lastSelectedMediaID, to: media.id)
            return
        }

        if modifiers.contains(.command) {
            if selectedMediaIDs.contains(media.id) {
                selectedMediaIDs.remove(media.id)
            } else {
                selectedMediaIDs.insert(media.id)
                lastSelectedMediaID = media.id
            }
            return
        }

        selectedMediaIDs = [media.id]
        lastSelectedMediaID = media.id
    }

    func selectAllVisible() {
        selectedMediaIDs = Set(visibleMedia.map(\.id))
        lastSelectedMediaID = visibleMedia.last?.id
    }

    func clearSelection() {
        selectedMediaIDs = []
        lastSelectedMediaID = nil
    }

    func loadThumbnailIfNeeded(for media: RemoteMedia) async {
        guard media.thumbnailURL == nil else {
            return
        }

        guard !thumbnailLoads.contains(media.id), !thumbnailQueued.contains(media.id) else {
            return
        }

        thumbnailQueued.insert(media.id)
        thumbnailQueue.append(media)
        processThumbnailQueue()
    }

    private func processThumbnailQueue() {
        guard activeThumbnailLoadCount < maxConcurrentThumbnailLoads else { return }

        while activeThumbnailLoadCount < maxConcurrentThumbnailLoads, !thumbnailQueue.isEmpty {
            let media = thumbnailQueue.removeFirst()
            thumbnailQueued.remove(media.id)

            guard visibleMedia.contains(where: { $0.id == media.id }) else {
                continue
            }

            thumbnailLoads.insert(media.id)
            activeThumbnailLoadCount += 1

            Task {
                await generateThumbnail(for: media)
            }
        }
    }

    private func generateThumbnail(for media: RemoteMedia) async {
        defer {
            thumbnailLoads.remove(media.id)
            activeThumbnailLoadCount = max(activeThumbnailLoadCount - 1, 0)
            processThumbnailQueue()
        }

        guard visibleMedia.contains(where: { $0.id == media.id }) else {
            return
        }

        do {
            let sourceURL = try await adbService.pullForThumbnail(media, deviceID: deviceStatus.deviceID)
            let thumbnailURL = try await thumbnailService.thumbnailURL(for: media, sourceURL: sourceURL)
            guard let index = visibleMedia.firstIndex(where: { $0.id == media.id }) else { return }
            visibleMedia[index].thumbnailURL = thumbnailURL
        } catch {
            guard let index = visibleMedia.firstIndex(where: { $0.id == media.id }) else { return }
            visibleMedia[index].thumbnailURL = nil
        }
    }

    private func resetThumbnailQueue() {
        thumbnailLoads = []
        thumbnailQueued = []
        thumbnailQueue = []
        activeThumbnailLoadCount = 0
    }

    func chooseDestinationAndTransfer() {
        guard canTransfer else { return }
        transferState = .choosingDestination

        let panel = NSOpenPanel()
        panel.title = L.chooseDestinationTitle
        panel.message = L.chooseDestinationMessage
        panel.prompt = L.choose
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let destination = panel.url else {
            transferState = .idle
            return
        }

        Task {
            await transfer(to: destination)
        }
    }

    func openTransferredFolder() {
        if case .finished(_, let url) = transferState {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func transfer(to destination: URL) async {
        let items = selectedMedia
        var summary = TransferSummary(total: items.count)
        transferState = .running(summary)

        for media in items {
            summary.currentFilename = media.filename
            transferState = .running(summary)

            do {
                try await adbService.pull(media, to: destination, deviceID: deviceStatus.deviceID)
                summary.completed += 1
            } catch {
                summary.failed += 1
            }

            transferState = .running(summary)
        }

        transferState = .finished(summary, destination)
    }

    private func selectRange(from firstID: RemoteMedia.ID, to secondID: RemoteMedia.ID) {
        guard
            let first = visibleMedia.firstIndex(where: { $0.id == firstID }),
            let second = visibleMedia.firstIndex(where: { $0.id == secondID })
        else {
            selectedMediaIDs.insert(secondID)
            lastSelectedMediaID = secondID
            return
        }

        let bounds = first <= second ? first...second : second...first
        selectedMediaIDs.formUnion(visibleMedia[bounds].map(\.id))
        lastSelectedMediaID = secondID
    }

    private func updateAlbum(_ id: Album.ID, mutate: (inout Album) -> Void) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        mutate(&albums[index])
    }
}
