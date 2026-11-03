import DeviceKit
import Foundation
import IconCore

enum LayoutSession {
    static func load(_ raw: [Any]) throws -> IconState {
        try IconCore.load(raw)
    }

    static func current(from device: DeviceOptions) throws -> (raw: [Any], state: IconState, hash: String) {
        let session = try device.open()
        let raw = try session.iconState()
        let state = try IconCore.load(raw, metrics: GridMetrics(deviceMetrics: try session.iconMetrics()))
        return (raw, state, try IconCore.stateHash(state))
    }
}
