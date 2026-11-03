import ArgumentParser
import DeviceKit

struct DevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List connected devices (JSON).")

    func run() throws {
        try printJSON(DeviceKit.connectedDevices())
    }
}
