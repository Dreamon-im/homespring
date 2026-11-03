import ArgumentParser
import DeviceKit
import Foundation
import IconCore

struct ApplyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Back up, recheck the base hash, write a planned layout, and verify it.")

    @OptionGroup var device: DeviceOptions
    @Argument(help: "A plan JSON file produced by `iconctl plan`.")
    var plan: String

    func run() throws {
        let saved = try JSONDecoder().decode(LayoutPlan.self, from: Data(contentsOf: URL(fileURLWithPath: plan)))
        let session = try device.open()
        let beforeRaw = try session.iconState()
        let before = try IconCore.load(beforeRaw, metrics: GridMetrics(deviceMetrics: try session.iconMetrics()))
        let beforeHash = try IconCore.stateHash(before)
        guard beforeHash == saved.baseHash else {
            throw LayoutError.staleBase(expected: saved.baseHash, actual: beforeHash)
        }
        let result = try IconCore.apply(saved.operations, to: before, expectedBaseHash: beforeHash)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = try AppPaths.directory("backups").appendingPathComponent("\(stamp).plist")
        try writePlist(beforeRaw, to: backup)
        try session.setIconState(IconCore.encode(result.state))
        let after = try IconCore.load(try readAfterWrite(session), metrics: before.metrics)
        let afterHash = try IconCore.stateHash(after)
        try printJSON(ApplyReport(
            backup: backup.path,
            verified: afterHash == saved.resultHash,
            expectedHash: saved.resultHash,
            actualHash: afterHash,
            diff: result.diff.jsonValue))
    }
}

struct ApplyReport: Codable {
    var backup: String
    var verified: Bool
    var expectedHash: String
    var actualHash: String
    var diff: DiffJSON
}
