import ArgumentParser
import DeviceKit
import Foundation
import IconCore

enum AppPaths {
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/homespring", isDirectory: true)
    }

    static func directory(_ name: String) throws -> URL {
        let url = support.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct BackupsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "backups", abstract: "List saved raw icon-state backups.")

    func run() throws {
        let directory = try AppPaths.directory("backups")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        let rows = try files.map { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return BackupRow(id: url.deletingPathExtension().lastPathComponent, bytes: values.fileSize ?? 0, modified: values.contentModificationDate)
        }
        try printJSON(rows)
    }
}

struct BackupRow: Codable {
    var id: String
    var bytes: Int
    var modified: Date?
}

struct SnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "snapshot", abstract: "Save the current raw icon state under a readable name.")

    @OptionGroup var device: DeviceOptions
    @Argument(help: "Letters, digits, dot, underscore, or hyphen.")
    var name: String

    func validate() throws {
        guard name.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ValidationError("Snapshot names may contain only letters, digits, dot, underscore, and hyphen.")
        }
    }

    func run() throws {
        let raw = try LayoutSession.current(from: device).raw
        let url = try AppPaths.directory("snapshots").appendingPathComponent("\(name).plist")
        try writePlist(raw, to: url)
        try printJSON(["saved": url.path])
    }
}

func writePlist(_ object: Any, to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    try data.write(to: url, options: .atomic)
}

func readAfterWrite(_ session: SpringBoardSession) throws -> [Any] {
    var lastError: Error?
    for _ in 0..<3 {
        do { return try session.iconState() } catch {
            lastError = error
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    throw lastError ?? CocoaError(.fileReadUnknown)
}

func readPlistArray(at url: URL) throws -> [Any] {
    let data = try Data(contentsOf: url)
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [Any] else {
        throw ValidationError("\(url.path) is not a property-list array.")
    }
    return value
}
