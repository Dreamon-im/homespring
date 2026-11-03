import Foundation

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

/// Prints a Foundation property list as JSON (see `jsonSafe` for lossy types).
func printJSONObject(_ object: Any) throws {
    let data = try JSONSerialization.data(
        withJSONObject: jsonSafe(object),
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    print(String(decoding: data, as: UTF8.self))
}

/// Dates become ISO-8601 strings and data becomes base64. Display only:
/// anything written back to the device must use the original plist.
func jsonSafe(_ value: Any) -> Any {
    switch value {
    case let dict as [String: Any]:
        return dict.mapValues(jsonSafe)
    case let array as [Any]:
        return array.map(jsonSafe)
    case let date as Date:
        return date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    case let data as Data:
        return data.base64EncodedString()
    default:
        return value
    }
}
