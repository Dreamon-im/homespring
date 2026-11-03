import CIMobileDevice

public struct DeviceError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

public struct ConnectedDevice: Codable, Sendable {
    public let udid: String
    public let connection: String  // "usb" or "network"
}

public enum DeviceKit {
    /// Devices currently visible to usbmuxd.
    public static func connectedDevices() -> [ConnectedDevice] {
        var list: UnsafeMutablePointer<idevice_info_t?>? = nil
        var count: Int32 = 0
        guard idevice_get_device_list_extended(&list, &count) == IDEVICE_E_SUCCESS, let list else {
            return []
        }
        defer { idevice_device_list_extended_free(list) }
        return (0..<Int(count)).compactMap { i in
            guard let info = list[i]?.pointee, let udid = info.udid else { return nil }
            let connection = info.conn_type == CONNECTION_NETWORK ? "network" : "usb"
            return ConnectedDevice(udid: String(cString: udid), connection: connection)
        }
    }
}
