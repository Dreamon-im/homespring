import ArgumentParser
import Foundation
import IconCore

struct FindCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find entries by name or ID. Multiple matches are all returned.")

    @OptionGroup var device: DeviceOptions
    @Argument(help: "A name fragment or identifier.")
    var query: String

    func run() throws {
        try printJSON(IconCore.find(query, in: LayoutSession.current(from: device).state))
    }
}
