import CIMobileDevice
import Foundation

public struct DeviceInfo: Codable, Sendable {
    public let udid: String
    public let name: String?
    public let productType: String?
    public let iosVersion: String?
    /// "usb" or "network" (Wi-Fi). Optional so older JSON still decodes.
    public let connection: String?
}

public struct GridMetrics: Codable, Sendable {
    public let cols: Int
    public let rows: Int
    public let dockMax: Int
    public let pageMax: Int

    /// Defaults used when the device omits a metric key.
    public init(metrics: [String: Any]) {
        func int(_ key: String, _ fallback: Int) -> Int {
            (metrics[key] as? NSNumber)?.intValue ?? fallback
        }
        cols = int("homeScreenIconColumns", 4)
        rows = int("homeScreenIconRows", 6)
        dockMax = int("homeScreenIconDockMaxCount", 4)
        pageMax = cols * rows
    }
}

/// One connection to `com.apple.springboardservices` on a USB or Wi-Fi device.
/// Commands are raw plists sent over property_list_service, the same protocol
/// libimobiledevice's sbservices wrapper lacks icon metrics.
public final class SpringBoardSession {
    public let info: DeviceInfo
    private let device: idevice_t
    private let client: property_list_service_client_t

    public init(udid: String? = nil) throws {
        let visible = DeviceKit.connectedDevices()
        if udid == nil {
            // The same iPhone is listed twice when it is on USB and Wi-Fi at once.
            if Set(visible.map(\.udid)).count > 1 {
                throw DeviceError("Several devices are connected; pass --udid (see `iconctl devices`).")
            }
        }

        // USB when plugged in, otherwise Wi-Fi (libimobiledevice prefers USB when both match).
        let lookup = idevice_options(rawValue: IDEVICE_LOOKUP_USBMUX.rawValue | IDEVICE_LOOKUP_NETWORK.rawValue)
        var dev: idevice_t?
        guard idevice_new_with_options(&dev, udid, lookup) == IDEVICE_E_SUCCESS, let dev else {
            throw DeviceError(udid.map { "Device \($0) not found over USB or Wi-Fi. Over Wi-Fi, a locked or sleeping iPhone disappears; unlock it and try again." }
                ?? "No iPhone found over USB or Wi-Fi. Connect it by USB (or turn on Wi-Fi sync in Finder), unlock it, and tap Trust on this Mac. Over Wi-Fi, a locked or sleeping iPhone disappears; unlock it and try again.")
        }

        var lockdown: lockdownd_client_t?
        let lerr = lockdownd_client_new_with_handshake(dev, &lockdown, "iconctl")
        guard lerr == LOCKDOWN_E_SUCCESS, let lockdown else {
            idevice_free(dev)
            throw DeviceError(Self.lockdownMessage(lerr))
        }
        defer { lockdownd_client_free(lockdown) }

        var udidPtr: UnsafeMutablePointer<CChar>?
        idevice_get_udid(dev, &udidPtr)
        let resolvedUDID = udidPtr.map { String(cString: $0) } ?? udid ?? ""
        free(udidPtr)

        var descriptor: lockdownd_service_descriptor_t?
        let serr = lockdownd_start_service(lockdown, "com.apple.springboardservices", &descriptor)
        guard serr == LOCKDOWN_E_SUCCESS, let descriptor else {
            idevice_free(dev)
            throw DeviceError("Could not start SpringBoard services (\(Self.lockdownMessage(serr))).")
        }
        defer { lockdownd_service_descriptor_free(descriptor) }

        var client: property_list_service_client_t?
        guard property_list_service_client_new(dev, descriptor, &client) == PROPERTY_LIST_SERVICE_E_SUCCESS,
              let client
        else {
            idevice_free(dev)
            throw DeviceError("Could not connect to SpringBoard services.")
        }

        self.info = DeviceInfo(
            udid: resolvedUDID,
            name: Self.value(lockdown, "DeviceName"),
            productType: Self.value(lockdown, "ProductType"),
            iosVersion: Self.value(lockdown, "ProductVersion"),
            connection: visible.contains { $0.udid == resolvedUDID && $0.connection == "usb" } ? "usb" : "network")
        self.device = dev
        self.client = client
    }

    deinit {
        property_list_service_client_free(client)
        idevice_free(device)
    }

    /// Raw icon state: index 0 is the Dock, then one array per page.
    public func iconState() throws -> [Any] {
        let reply = try request(["command": "getIconState", "formatVersion": "2"])
        guard let state = reply as? [Any] else {
            throw DeviceError("Unexpected getIconState reply: \(type(of: reply))")
        }
        return state
    }

    /// Replaces the complete icon state. SpringBoard applies this command without
    /// sending a plist reply, so waiting for one makes a successful write look failed.
    public func setIconState(_ state: [Any]) throws {
        let node = try PlistBridge.node(from: ["command": "setIconState", "iconState": state])
        defer { plist_free(node) }
        guard property_list_service_send_binary_plist(client, node) == PROPERTY_LIST_SERVICE_E_SUCCESS else {
            throw DeviceError("Failed to send setIconState to SpringBoard.")
        }
    }

    public func iconMetrics() throws -> [String: Any] {
        let reply = try request(["command": "getHomeScreenIconMetrics"])
        guard let metrics = reply as? [String: Any] else {
            throw DeviceError("Unexpected getHomeScreenIconMetrics reply: \(type(of: reply))")
        }
        return metrics
    }

    private func request(_ command: [String: Any]) throws -> Any {
        let node = try PlistBridge.node(from: command)
        defer { plist_free(node) }
        guard property_list_service_send_binary_plist(client, node) == PROPERTY_LIST_SERVICE_E_SUCCESS else {
            throw DeviceError("Failed to send \(command["command"] ?? "command") to SpringBoard.")
        }
        var reply: plist_t?
        let err = property_list_service_receive_plist_with_timeout(client, &reply, 30_000)
        guard err == PROPERTY_LIST_SERVICE_E_SUCCESS, let reply else {
            throw DeviceError("No reply from SpringBoard for \(command["command"] ?? "command") (error \(err.rawValue)).")
        }
        defer { plist_free(reply) }
        return try PlistBridge.object(from: reply)
    }

    private static func value(_ lockdown: lockdownd_client_t, _ key: String) -> String? {
        var node: plist_t?
        guard lockdownd_get_value(lockdown, nil, key, &node) == LOCKDOWN_E_SUCCESS, let node else { return nil }
        defer { plist_free(node) }
        return (try? PlistBridge.object(from: node)) as? String
    }

    private static func lockdownMessage(_ err: lockdownd_error_t) -> String {
        switch err {
        case LOCKDOWN_E_PASSWORD_PROTECTED:
            return "The iPhone is locked. Unlock it and try again."
        case LOCKDOWN_E_PAIRING_DIALOG_RESPONSE_PENDING:
            return "Tap Trust on the iPhone, then try again."
        case LOCKDOWN_E_USER_DENIED_PAIRING:
            return "Pairing was denied on the iPhone. Reconnect and tap Trust."
        case LOCKDOWN_E_INVALID_HOST_ID, LOCKDOWN_E_PAIRING_FAILED:
            return "This Mac is not paired with the iPhone. Reconnect and tap Trust."
        default:
            return "lockdownd error \(err.rawValue)"
        }
    }
}
