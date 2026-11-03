import CryptoKit
import Foundation

public struct LayoutOptions: Equatable, Sendable {
    public var folderPageSize: Int

    public init(folderPageSize: Int = 9) {
        precondition(folderPageSize > 0, "A folder page must hold at least one icon.")
        self.folderPageSize = folderPageSize
    }
}

/// Parses and encodes a SpringBoard icon state without narrowing its fields.
public enum LayoutStore {
    public static func load(_ raw: [Any], metrics: GridMetrics = GridMetrics(), options: LayoutOptions = LayoutOptions()) throws -> IconState {
        var resolved = metrics
        resolved.folderPageSize = options.folderPageSize
        let pages = try raw.enumerated().map { index, page in
            guard let entries = page as? [Any] else {
                throw LayoutError.malformed("Page \(index) is not an array.")
            }
            return try entries.enumerated().map { entryIndex, entry in
                try decode(entry, at: "page \(index)[\(entryIndex)]")
            }
        }
        return IconState(pages: pages, metrics: resolved)
    }

    public static func encode(_ state: IconState) -> [Any] {
        state.pages.map { page in page.map(encodeEntry) }
    }

    /// SHA-256 of a canonical plist. Dictionary key order cannot change it.
    public static func stateHash(_ state: IconState) throws -> String {
        let data = try CanonicalPlist.data(encode(state))
        return CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func requireBaseHash(_ expected: String, matches state: IconState) throws {
        let actual = try stateHash(state)
        guard actual == expected.lowercased() else {
            throw LayoutError.staleBase(expected: expected, actual: actual)
        }
    }

    static func decode(_ value: Any, at path: String) throws -> IconEntry {
        guard let fields = value as? PlistDictionary else {
            throw LayoutError.malformed("\(path) is not a dictionary.")
        }
        // A Smart Stack lists its widgets in `elements` and always carries an empty
        // iconLists; it must not be mistaken for an empty folder.
        let isStack = fields["elements"] is [Any]
        if fields["elementType"] as? String == "widget" || isStack {
            if let lists = fields["iconLists"], (lists as? [Any])?.isEmpty != true {
                throw LayoutError.unsupportedWidget("\(path) is both a widget and a folder.")
            }
            let name = isStack ? "Smart Stack" : widgetName(fields)
            let entry = IconEntry(fields: fields, kind: .widget, id: nil, name: name, installState: .unknown)
            _ = try entry.gridSpan()
            return entry
        }
        if let lists = fields["iconLists"] {
            guard let pages = lists as? [Any] else {
                throw LayoutError.malformed("\(path) has a non-array iconLists.")
            }
            let decoded = try pages.enumerated().map { pageIndex, page in
                guard let entries = page as? [Any] else {
                    throw LayoutError.malformed("\(path) folder page \(pageIndex) is not an array.")
                }
                return try entries.enumerated().map { entryIndex, entry in
                    let child = try decode(entry, at: "\(path)/folder \(pageIndex)[\(entryIndex)]")
                    if child.kind == .folder {
                        throw LayoutError.nestedFolder("A folder contains another folder at \(path).")
                    }
                    return child
                }
            }
            let name = (fields["displayName"] as? String) ?? ""
            return IconEntry(
                fields: fields.filter { $0.key != "iconLists" },
                kind: .folder,
                id: nil,
                name: name,
                installState: .unknown,
                folderPages: decoded)
        }
        if PlistValue.isPresent("webClipURL", in: fields) {
            let id = fields["displayIdentifier"] as? String
            return IconEntry(
                fields: fields,
                kind: .webclip,
                id: (id?.isEmpty == false) ? id : nil,
                name: (fields["displayName"] as? String) ?? "",
                installState: .unknown)
        }
        let bundleID = fields["bundleIdentifier"] as? String
        let displayID = fields["displayIdentifier"] as? String
        let version = fields["bundleVersion"] as? String
        let usableBundle = (bundleID?.isEmpty == false) ? bundleID : nil
        let usableDisplay = (displayID?.isEmpty == false) ? displayID : nil
        let id = usableBundle ?? usableDisplay
        let installed = usableBundle != nil && version?.isEmpty == false
        return IconEntry(
            fields: fields,
            kind: id == nil ? .unknown : .app,
            id: id,
            name: (fields["displayName"] as? String) ?? "",
            installState: installed ? .installed : (id == nil ? .unknown : .offloaded))
    }

    static func encodeEntry(_ entry: IconEntry) -> PlistDictionary {
        var fields = entry.fields
        if entry.kind == .folder {
            fields["iconLists"] = entry.folderPages.map { page in page.map(encodeEntry) }
        }
        return fields
    }

    private static func widgetName(_ fields: PlistDictionary) -> String {
        if let name = fields["displayName"] as? String, !name.isEmpty { return name }
        return (fields["containerBundleIdentifier"] as? String) ?? ""
    }

    static func folderIndex(_ state: IconState) throws -> [String: PageRef] {
        var result: [String: [PageRef]] = [:]
        for (pageNumber, page) in state.pages.enumerated() where pageNumber > 0 {
            for (index, entry) in page.enumerated() where entry.kind == .folder {
                let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw LayoutError.malformed("A folder on page \(pageNumber) has no display name.")
                }
                result[name, default: []].append(PageRef(page: pageNumber, index: index))
            }
        }
        var unique: [String: PageRef] = [:]
        for (name, refs) in result {
            guard refs.count == 1 else { throw LayoutError.ambiguousFolder(name) }
            unique[name] = refs[0]
        }
        return unique
    }
}

struct PageRef: Equatable {
    var page: Int
    var index: Int
}

enum CanonicalPlist {
    /// A deterministic encoding: dictionaries become sorted key/value pairs, so the
    /// hash does not depend on how a plist implementation orders dictionary keys.
    static func data(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: canonical(value), format: .binary, options: 0)
    }

    private static func canonical(_ value: Any) -> Any {
        switch value {
        case let dictionary as PlistDictionary:
            return dictionary.keys.sorted().map { key in [key, canonical(dictionary[key]!)] }
        case let array as [Any]:
            return array.map(canonical)
        case let date as Date:
            return ["date", date.timeIntervalSinceReferenceDate.bitPattern]
        case let data as Data:
            return ["data", data]
        case let number as NSNumber:
            return ["number", number.stringValue, String(cString: number.objCType)]
        default:
            return value
        }
    }
}
