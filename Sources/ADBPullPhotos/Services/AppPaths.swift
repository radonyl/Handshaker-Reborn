import Foundation

enum AppPaths {
    static var projectRoot: URL {
        if let envRoot = ProcessInfo.processInfo.environment["ADB_PULL_PHOTOS_ROOT"], !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot, isDirectory: true)
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: currentDirectory.appending(path: "cfg/pull_camera.ini").path) {
            return currentDirectory
        }

        if let resourceURL = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resourceURL.appending(path: "cfg/pull_camera.ini").path) {
            return resourceURL
        }

        return currentDirectory
    }

    static var configURL: URL {
        projectRoot.appending(path: "cfg/pull_camera.ini")
    }

    static var thumbnailCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "ADBPullPhotos/Thumbnails", directoryHint: .isDirectory)
    }
}
