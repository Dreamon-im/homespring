import ArgumentParser
import DeviceKit
import Foundation
import IconCore

struct RestoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Restore a raw backup. A fresh backup is written first.")

    @OptionGroup var device: DeviceOptions
    @Argument(help: "Backup ID from `iconctl backups`, without .plist.")
    var id: String
    @Flag(help: "Preview the difference without writing.")
    var dryRun = false

    func validate() throws {
        guard id.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil else {
            throw ValidationError("Invalid backup ID.")
        }
    }

    func run() throws {
        let source = try AppPaths.directory("backups").appendingPathComponent("\(id).plist")
        let raw = try readPlistArray(at: source)
        let session = try device.open()
        let metrics = try session.iconMetrics()
        let currentRaw = try session.iconState()
        let current = try IconCore.load(currentRaw, metrics: GridMetrics(deviceMetrics: metrics))
        let target = try IconCore.load(raw, metrics: current.metrics)
        let diff = try LayoutQuery.diff(from: current, to: target, requestedIDs: [])
        if dryRun {
            try printJSON(RestorePreview(dryRun: true, diff: diff.jsonValue))
            return
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = try AppPaths.directory("backups").appendingPathComponent("before-restore-\(stamp).plist")
        try writePlist(currentRaw, to: backup)
        try session.setIconState(raw)
        let after = try IconCore.load(try readAfterWrite(session), metrics: current.metrics)
        try printJSON(RestoreReport(
            backup: backup.path,
            verified: try IconCore.stateHash(after) == IconCore.stateHash(target)))
    }
}

struct RestorePreview: Codable {
    var dryRun: Bool
    var diff: DiffJSON
}

struct RestoreReport: Codable {
    var backup: String
    var verified: Bool
}
