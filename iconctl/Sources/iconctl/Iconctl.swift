import ArgumentParser
import DeviceKit
import IconCore

@main
struct Iconctl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iconctl",
        abstract: "Read and rearrange an iPhone home screen over USB or Wi-Fi.",
        version: IconCore.version,
        subcommands: [
            DevicesCommand.self,
            DeviceCommand.self,
            DumpCommand.self,
            RenderCommand.self,
            FindCommand.self,
            PlanCommand.self,
            ApplyCommand.self,
            BackupsCommand.self,
            RestoreCommand.self,
            SnapshotCommand.self,
        ]
    )
}

struct DeviceOptions: ParsableArguments {
    @Option(help: "UDID of the device (default: the only connected device, over USB if plugged in, else Wi-Fi).")
    var udid: String?

    func open() throws -> SpringBoardSession {
        try SpringBoardSession(udid: udid)
    }
}
