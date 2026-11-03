import ArgumentParser
import DeviceKit
import Foundation
import IconCore

struct DumpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dump",
        abstract: "Print the home-screen inventory, or the raw SpringBoard state with --raw.")

    @OptionGroup var device: DeviceOptions

    @Flag(help: "Print the raw SpringBoard icon state as JSON (dates as ISO-8601, data as base64).")
    var raw = false

    @Option(help: "Also save the raw state, losslessly, as a binary plist at this path.")
    var save: String?

    func run() throws {
        let rawState = try device.open().iconState()
        if let save {
            let data = try PropertyListSerialization.data(fromPropertyList: rawState, format: .binary, options: 0)
            try data.write(to: URL(fileURLWithPath: save))
        }
        if raw {
            try printJSONObject(rawState)
        } else {
            try printJSON(IconCore.inventory(try LayoutSession.load(rawState)))
        }
    }
}
