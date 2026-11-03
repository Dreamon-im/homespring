import ArgumentParser
import DeviceKit
import Foundation

struct DeviceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "Device name, iOS version and home screen grid (JSON).")

    @OptionGroup var device: DeviceOptions

    struct Report: Encodable {
        let device: DeviceInfo
        let grid: GridMetrics
        let metrics: [String: Double]
    }

    func run() throws {
        let session = try device.open()
        let metrics = try session.iconMetrics()
        try printJSON(Report(
            device: session.info,
            grid: GridMetrics(metrics: metrics),
            metrics: metrics.compactMapValues { ($0 as? NSNumber)?.doubleValue }))
    }
}
