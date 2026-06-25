import Foundation

enum ADBError: LocalizedError {
    case commandFailed(String)
    case noAuthorizedDevice
    case adbNotFound

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message
        case .noAuthorizedDevice:
            L.noAuthorizedDevice
        case .adbNotFound:
            L.adbMissingError
        }
    }
}

struct ADBService {
    private let adbExecutable: String?
    private let albumScanRoots = [
        "/sdcard/DCIM",
        "/sdcard/Pictures",
        "/sdcard/Movies",
        "/sdcard/Download"
    ]

    init(adbExecutable: String? = ADBService.resolveADBExecutable()) {
        self.adbExecutable = adbExecutable
    }

    func scanAlbums(deviceID: String?) async throws -> [Album] {
        let roots = albumScanRoots.map(Self.shellQuote).joined(separator: " ")
        let command = """
        for d in \(roots) /sdcard/DCIM/* /sdcard/Pictures/* /sdcard/Movies/* /sdcard/Download/*; do [ -d "$d" ] || continue; find "$d" -maxdepth 1 -type f 2>/dev/null | while IFS= read -r f; do case "${f##*.}" in jpg|JPG|jpeg|JPEG|png|PNG|webp|WEBP|heic|HEIC|gif|GIF|mp4|MP4|mov|MOV|mkv|MKV|3gp|3GP|webm|WEBM) printf '? %s\\n' "$d"; break;; esac; done; done | sort -u
        """

        let output = try await adbShell(command, deviceID: deviceID)
        return output
            .components(separatedBy: .newlines)
            .compactMap(parseAlbumCountLine)
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func deviceStatus(configDeviceID: String?) async -> DeviceStatus {
        guard adbExecutable != nil else {
            return DeviceStatus(
                adbAvailable: false,
                connected: false,
                authorized: false,
                deviceID: nil,
                message: L.adbMissingTitle,
                detail: L.adbMissingDetail
            )
        }

        do {
            _ = try await adb(["version"])
        } catch {
            return DeviceStatus(
                adbAvailable: false,
                connected: false,
                authorized: false,
                deviceID: nil,
                message: L.adbCannotRun,
                detail: error.localizedDescription
            )
        }

        do {
            let result = try await adb(["devices"])
            let devices = parseDevices(result.stdout)

            if let configDeviceID, !configDeviceID.isEmpty {
                if devices.authorized.contains(configDeviceID) {
                    return DeviceStatus(
                        adbAvailable: true,
                        connected: true,
                        authorized: true,
                        deviceID: configDeviceID,
                        message: L.connected(configDeviceID),
                        detail: nil
                    )
                }

                if devices.unauthorized.contains(configDeviceID) {
                    return DeviceStatus(
                        adbAvailable: true,
                        connected: true,
                        authorized: false,
                        deviceID: configDeviceID,
                        message: L.waitingAuthorization(configDeviceID),
                        detail: L.authorizationDetail
                    )
                }

                return DeviceStatus(
                    adbAvailable: true,
                    connected: false,
                    authorized: false,
                    deviceID: configDeviceID,
                    message: L.configuredDeviceMissing,
                    detail: L.configuredDeviceMissingDetail
                )
            }

            if let first = devices.authorized.first {
                return DeviceStatus(
                    adbAvailable: true,
                    connected: true,
                    authorized: true,
                    deviceID: first,
                    message: L.connected(first),
                    detail: nil
                )
            }

            if let first = devices.unauthorized.first {
                return DeviceStatus(
                    adbAvailable: true,
                    connected: true,
                    authorized: false,
                    deviceID: first,
                    message: L.waitingAuthorization(),
                    detail: L.authorizationDetail
                )
            }

            return DeviceStatus(
                adbAvailable: true,
                connected: false,
                authorized: false,
                deviceID: nil,
                message: L.phoneNotConnected,
                detail: L.phoneNotConnectedDetail
            )
        } catch {
            return DeviceStatus(
                adbAvailable: true,
                connected: false,
                authorized: false,
                deviceID: nil,
                message: error.localizedDescription,
                detail: nil
            )
        }
    }

    func listMedia(in album: Album, deviceID: String?, offset: Int, limit: Int) async throws -> [RemoteMedia] {
        let quotedRemote = Self.shellQuote(album.remotePath)
        let start = max(offset + 1, 1)
        let end = max(offset + limit, start)
        let command = """
        d=\(quotedRemote); cd "$d" 2>/dev/null || exit 0; ls -1t 2>/dev/null | sed -n '\(start),\(end)p' | while IFS= read -r n; do [ -f "$n" ] || continue; case "${n##*.}" in jpg|JPG|jpeg|JPEG|png|PNG|webp|WEBP|heic|HEIC|gif|GIF|mp4|MP4|mov|MOV|mkv|MKV|3gp|3GP|webm|WEBM) stat -c '%Y\t%s\t%n' "$d/$n" 2>/dev/null;; esac; done
        """

        let result = try await adbShell(command, deviceID: deviceID)
        return result
            .components(separatedBy: .newlines)
            .compactMap { parseMediaStatLine($0, albumID: album.id) }
    }

    func pull(_ media: RemoteMedia, to targetDirectory: URL, deviceID: String?) async throws {
        let destination = uniqueDestination(for: media.filename, in: targetDirectory)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".part")

        if FileManager.default.fileExists(atPath: temporary.path) {
            try? FileManager.default.removeItem(at: temporary)
        }

        let result = try await adb(["pull", media.remotePath, temporary.path], deviceID: deviceID)
        guard result.exitCode == 0 else {
            throw ADBError.commandFailed(result.stderr.isEmpty ? L.transferFailed(media.filename) : result.stderr)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    func pullForThumbnail(_ media: RemoteMedia, deviceID: String?) async throws -> URL {
        try FileManager.default.createDirectory(
            at: AppPaths.thumbnailCacheURL,
            withIntermediateDirectories: true
        )

        let sourceURL = AppPaths.thumbnailCacheURL
            .appendingPathComponent(Self.cacheKey(for: media.remotePath))
            .appendingPathExtension(URL(fileURLWithPath: media.filename).pathExtension)

        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        let result = try await adb(["pull", media.remotePath, sourceURL.path], deviceID: deviceID)
        guard result.exitCode == 0 else {
            throw ADBError.commandFailed(result.stderr.isEmpty ? L.thumbnailCacheFailed(media.filename) : result.stderr)
        }

        return sourceURL
    }

    private func adb(_ arguments: [String], deviceID: String? = nil) async throws -> ShellResult {
        guard let adbExecutable else {
            throw ADBError.adbNotFound
        }

        var args: [String] = []
        if let deviceID, !deviceID.isEmpty {
            args.append(contentsOf: ["-s", deviceID])
        }
        args.append(contentsOf: arguments)

        let result = try await Shell.run(adbExecutable, args)
        if result.exitCode != 0 && arguments.first != "devices" {
            throw ADBError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result
    }

    private func adbShell(_ command: String, deviceID: String?) async throws -> String {
        let result = try await adb(["shell", command], deviceID: deviceID)
        guard result.exitCode == 0 else {
            throw ADBError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func parseDevices(_ output: String) -> (authorized: [String], unauthorized: [String]) {
        var authorized: [String] = []
        var unauthorized: [String] = []

        for line in output.components(separatedBy: .newlines).dropFirst() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }

            let id = String(parts[0])
            let state = String(parts[1])

            if state == "device" {
                authorized.append(id)
            } else if state == "unauthorized" {
                unauthorized.append(id)
            }
        }

        return (authorized, unauthorized)
    }

    private func parseAlbumCountLine(_ line: String) -> Album? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }

        let countText = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmed[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        let name = URL(fileURLWithPath: path).lastPathComponent

        return Album(
            id: path,
            name: name.isEmpty ? path : name,
            remotePath: path,
            localPath: "",
            enabled: true,
            scanState: .idle,
            mediaCount: Int(countText)
        )
    }

    private func parseMediaStatLine(_ line: String, albumID: String) -> RemoteMedia? {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        let timestampText = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeText = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let path = String(parts[2])
        let filename = URL(fileURLWithPath: path).lastPathComponent

        guard let mediaType = MediaType.infer(from: filename) else {
            return nil
        }

        let timestamp = TimeInterval(timestampText)

        return RemoteMedia(
            id: path,
            remotePath: path,
            filename: filename,
            mediaType: mediaType,
            size: Int64(sizeText),
            modifiedAt: timestamp.map { Date(timeIntervalSince1970: $0) },
            albumID: albumID,
            transferred: false,
            thumbnailURL: nil
        )
    }

    private func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let original = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: original.path) else {
            return original
        }

        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension

        for index in 1...999 {
            let candidateName = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent(UUID().uuidString + "-" + filename)
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func cacheKey(for remotePath: String) -> String {
        remotePath
            .data(using: .utf8)?
            .map { String(format: "%02x", $0) }
            .joined() ?? UUID().uuidString
    }

    static func resolveADBExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if let explicit = environment["ADB_PATH"], !explicit.isEmpty {
            candidates.append(explicit)
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appending(path: "platform-tools/adb").path)
        }

        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.append(URL(fileURLWithPath: root).appending(path: "platform-tools/adb").path)
            }
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "\(NSHomeDirectory())/Android/Sdk/platform-tools/adb"
        ])

        if let pathValue = environment["PATH"] {
            for directory in pathValue.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(directory)).appending(path: "adb").path)
            }
        }

        return candidates.first { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
    }
}
