import CIMobileDevice
import Foundation

/// Converts between libplist nodes and Foundation property lists via binary plist,
/// so every field (dates, data, unknown keys) round-trips with its original type.
enum PlistBridge {
    static func object(from node: plist_t) throws -> Any {
        var bytes: UnsafeMutablePointer<CChar>?
        var length: UInt32 = 0
        guard plist_to_bin(node, &bytes, &length) == PLIST_ERR_SUCCESS, let bytes else {
            throw DeviceError("plist_to_bin failed")
        }
        defer { plist_mem_free(bytes) }
        return try PropertyListSerialization.propertyList(
            from: Data(bytes: bytes, count: Int(length)), format: nil)
    }

    /// Caller owns the returned node and must `plist_free` it.
    static func node(from object: Any) throws -> plist_t {
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        var node: plist_t?
        let err = data.withUnsafeBytes { raw in
            plist_from_bin(raw.bindMemory(to: CChar.self).baseAddress, UInt32(raw.count), &node)
        }
        guard err == PLIST_ERR_SUCCESS, let node else {
            throw DeviceError("plist_from_bin failed")
        }
        return node
    }
}
