import ArgumentParser
import Foundation
import IconCore

struct PlanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Validate operations and print their diff without writing the device.")

    @OptionGroup var device: DeviceOptions
    @Argument(help: "A JSON array of layout operations.")
    var operations: String
    @Option(name: .shortAndLong, help: "Write the resulting plan JSON to this path.")
    var output: String?

    func run() throws {
        let current = try LayoutSession.current(from: device)
        let operations = try OperationJSON.decode(Data(contentsOf: URL(fileURLWithPath: operations)))
        let result = try IconCore.apply(operations, to: current.state, expectedBaseHash: current.hash)
        let plan = LayoutPlan(
            baseHash: current.hash,
            resultHash: try IconCore.stateHash(result.state),
            operations: operations,
            diff: result.diff.jsonValue)
        let data = try LayoutPlan.encode(plan)
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
        }
        print(String(decoding: data, as: UTF8.self))
    }
}
