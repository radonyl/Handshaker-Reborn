import Foundation

struct AppConfiguration {
    var deviceID: String?
    var albums: [Album]
}

enum ConfigStore {
    static func load(from url: URL = AppPaths.configURL) throws -> AppConfiguration {
        let text = try String(contentsOf: url, encoding: .utf8)
        let sections = parseINI(text)

        let deviceID = sections["adb"]?["device_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDeviceID = deviceID?.isEmpty == false ? deviceID : nil

        let albums = sections
            .filter { key, _ in key.hasPrefix("job.") }
            .compactMap { section, values -> Album? in
                let enabled = values["enabled"].map { $0.lowercased() != "false" } ?? true
                guard enabled else { return nil }
                guard let remote = values["remote"]?.trimmingCharacters(in: .whitespacesAndNewlines), !remote.isEmpty else {
                    return nil
                }

                let id = String(section.dropFirst("job.".count))
                let local = values["local"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Album(
                    id: id,
                    name: id.displayAlbumName,
                    remotePath: remote.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? remote : remote.trimmingCharacters(in: .whitespacesAndNewlines),
                    localPath: local,
                    enabled: enabled
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return AppConfiguration(deviceID: normalizedDeviceID, albums: albums)
    }

    private static func parseINI(_ text: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var currentSection = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else {
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast())
                sections[currentSection, default: [:]] = [:]
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            sections[currentSection, default: [:]][key] = value
        }

        return sections
    }
}

private extension String {
    var displayAlbumName: String {
        split(separator: "_")
            .flatMap { $0.split(separator: "-") }
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}
