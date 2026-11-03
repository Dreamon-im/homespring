import Foundation

/// A property-list dictionary whose original keys and value types are retained.
public typealias PlistDictionary = [String: Any]

/// Property-list values are immutable once read, but `Any` cannot prove that to Swift 6.
/// The box copies its dictionary and never mutates it.
struct PlistFields: Equatable, @unchecked Sendable {
    let value: PlistDictionary

    init(_ value: PlistDictionary) {
        self.value = value
    }

    static func == (lhs: PlistFields, rhs: PlistFields) -> Bool {
        PlistValue.dictionariesEqual(lhs.value, rhs.value)
    }
}

enum PlistValue {
    static func isPresent(_ key: String, in fields: PlistDictionary) -> Bool {
        guard let value = fields[key] else { return false }
        return !(value is NSNull)
    }

    /// Compares values that `PropertyListSerialization` can produce.
    static func equals(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (left as NSNumber, right as NSNumber):
            return left == right
        case let (left as String, right as String):
            return left == right
        case let (left as Date, right as Date):
            return left == right
        case let (left as Data, right as Data):
            return left == right
        case let (left as [Any], right as [Any]):
            return left.count == right.count && zip(left, right).allSatisfy(equals)
        case let (left as PlistDictionary, right as PlistDictionary):
            return dictionariesEqual(left, right)
        default:
            return false
        }
    }

    static func dictionariesEqual(_ lhs: PlistDictionary, _ rhs: PlistDictionary) -> Bool {
        lhs.count == rhs.count && lhs.keys.allSatisfy { key in
            guard let right = rhs[key] else { return false }
            return equals(lhs[key]!, right)
        }
    }
}
