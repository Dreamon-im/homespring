import ArgumentParser
import Foundation
import IconCore

struct RenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render the home screen as estimated text grids.")

    @OptionGroup var device: DeviceOptions

    func run() throws {
        print(try IconCore.render(LayoutSession.current(from: device).state))
    }
}
