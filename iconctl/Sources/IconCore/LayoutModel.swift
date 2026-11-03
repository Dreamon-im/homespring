import CryptoKit
import Foundation

/// Device grid used for capacity and estimated positions.
///
/// `folderPageSize` is not a device metric. SpringBoard paginates a folder at nine
/// icons, and that is the default; tests can set another size.
public struct GridMetrics: Equatable, Sendable {
    public var rows: Int
    public var cols: Int
    public var dockMax: Int
    public var folderPageSize: Int

    public var pageMax: Int { rows * cols }

    public init(rows: Int = 6, cols: Int = 4, dockMax: Int = 4, folderPageSize: Int = 9) {
        precondition(rows > 0 && cols > 0 && dockMax >= 0 && folderPageSize > 0)
        self.rows = rows
        self.cols = cols
        self.dockMax = dockMax
        self.folderPageSize = folderPageSize
    }

    /// Reads the keys DeviceKit returns. Missing keys use conservative fallbacks.
    public init(deviceMetrics: [String: Any], folderPageSize: Int = 9) {
        func integer(_ key: String, _ fallback: Int) -> Int {
            if let number = deviceMetrics[key] as? NSNumber { return number.intValue }
            if let number = deviceMetrics[key] as? Int { return number }
            return fallback
        }
        self.init(
            rows: integer("homeScreenIconRows", 6),
            cols: integer("homeScreenIconColumns", 4),
            dockMax: integer("homeScreenIconDockMaxCount", 4),
            folderPageSize: folderPageSize)
    }
}

public enum InstallState: String, Codable, Equatable, Sendable {
    /// Has both a bundle identifier and a bundle version.
    case installed
    /// Not a folder, widget, or web clip, and missing either its bundle identifier or version.
    case offloaded
    /// No stable identifier, so an operation cannot address it.
    case unknown
}

public enum EntryKind: String, Codable, Equatable, Sendable {
    case app
    case webclip
    case folder
    case widget
    case unknown
}

public struct IconLocation: Codable, Equatable, Sendable {
    public enum Container: Codable, Equatable, Sendable {
        case dock
        case page(Int)
        case folder(name: String, page: Int, folderPage: Int)
    }

    public var container: Container
    /// Zero-based position among the entries of that container, including widgets.
    public var index: Int
    /// Estimated one-based grid cell. Empty when the entry does not fit.
    public var row: Int?
    public var col: Int?

    public init(container: Container, index: Int, row: Int? = nil, col: Int? = nil) {
        self.container = container
        self.index = index
        self.row = row
        self.col = col
    }
}

/// One SpringBoard entry. The original dictionary is retained verbatim.
public struct IconEntry: Equatable, Sendable {
    var storedFields: PlistFields
    public var kind: EntryKind
    public var id: String?
    public var name: String
    public var installState: InstallState
    public var folderPages: [[IconEntry]]

    init(
        fields: PlistDictionary,
        kind: EntryKind,
        id: String?,
        name: String,
        installState: InstallState,
        folderPages: [[IconEntry]] = []
    ) {
        self.storedFields = PlistFields(fields)
        self.kind = kind
        self.id = id
        self.name = name
        self.installState = installState
        self.folderPages = folderPages
    }

    /// Original plist fields. Reassigning replaces the whole dictionary; callers do not mutate it in place.
    public var fields: PlistDictionary {
        get { storedFields.value }
        set { storedFields = PlistFields(newValue) }
    }

    public var webClipURL: String? { fields["webClipURL"] as? String }
    public var bundleIdentifier: String? { fields["bundleIdentifier"] as? String }
    public var bundleVersion: String? { fields["bundleVersion"] as? String }

    /// Cells occupied on a page. Unknown widget sizes are not guessed.
    public func gridSpan() throws -> (width: Int, height: Int) {
        guard kind == .widget else { return (1, 1) }
        guard let size = fields["gridSize"] as? String else {
            throw LayoutError.unsupportedWidget("A widget has no gridSize, so its cells cannot be reserved.")
        }
        switch size {
        case "small": return (2, 2)
        case "medium": return (4, 2)
        case "large": return (4, 4)
        default:
            throw LayoutError.unsupportedWidget("Widget gridSize \(size) is not supported.")
        }
    }
}

public struct IconState: Equatable, Sendable {
    /// Index 0 is the Dock. Later indices are home-screen pages.
    public var pages: [[IconEntry]]
    public var metrics: GridMetrics

    public init(pages: [[IconEntry]], metrics: GridMetrics) {
        self.pages = pages
        self.metrics = metrics
    }
}

public enum Position: Equatable, Sendable {
    case end
    case start
    case before(id: String)
    case after(id: String)
    case index(Int)
    /// Insert among apps, web clips, and folders by localized name.
    /// Widgets stay exactly where they are, so this is refused when one is present.
    case sorted
}

public enum LayoutDestination: Equatable, Sendable {
    case dock
    case page(Int)
    case folder(name: String)
}

public struct LayoutBatch: Equatable, Sendable {
    public var operations: [LayoutOperation]
    public var expectedBaseHash: String?

    public init(operations: [LayoutOperation], expectedBaseHash: String? = nil) {
        self.operations = operations
        self.expectedBaseHash = expectedBaseHash
    }
}

public enum LayoutOperation: Equatable, Sendable {
    case move(id: String, to: LayoutDestination, position: Position = .end)
    case swap(String, String)
    case createFolder(page: Int, name: String, ids: [String], position: Position = .end)
    case renameFolder(from: String, to: String)
    case sortFolder(name: String, by: SortKey = .name)

    public enum SortKey: String, Equatable, Sendable {
        case name
    }
}

public struct InventoryItem: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String
    public var kind: EntryKind
    public var installState: InstallState
    public var location: IconLocation
    public var webClipURL: String?
    public var bundleVersion: String?

    public init(
        id: String?,
        name: String,
        kind: EntryKind,
        installState: InstallState,
        location: IconLocation,
        webClipURL: String? = nil,
        bundleVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.installState = installState
        self.location = location
        self.webClipURL = webClipURL
        self.bundleVersion = bundleVersion
    }
}

public struct LayoutDiff: Codable, Equatable, Sendable {
    public var requested: [EntryChange]
    public var incidental: [EntryChange]
    public var removed: [EntryChange]

    public init(requested: [EntryChange] = [], incidental: [EntryChange] = [], removed: [EntryChange] = []) {
        self.requested = requested
        self.incidental = incidental
        self.removed = removed
    }
}

public struct EntryChange: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var from: IconLocation?
    public var to: IconLocation?

    public init(id: String, name: String, from: IconLocation? = nil, to: IconLocation? = nil) {
        self.id = id
        self.name = name
        self.from = from
        self.to = to
    }
}

public enum LayoutError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case ambiguousFolder(String)
    case notFound(String)
    case duplicateID(String)
    case unknownID(String)
    case nestedFolder(String)
    case folderInDock(String)
    case emptyFolder(String)
    case capacity(String)
    case unsupportedWidget(String)
    case widgetMoved(String)
    case invalidPosition(String)
    case staleBase(expected: String, actual: String)

    public var description: String {
        switch self {
        case .malformed(let message),
             .notFound(let message),
             .unknownID(let message),
             .nestedFolder(let message),
             .folderInDock(let message),
             .emptyFolder(let message),
             .capacity(let message),
             .unsupportedWidget(let message),
             .widgetMoved(let message),
             .invalidPosition(let message):
            return message
        case .ambiguousFolder(let name):
            return "More than one folder is named \(name); refusing to guess."
        case .duplicateID(let id):
            return "\(id) appears more than once."
        case .staleBase(let expected, let actual):
            return "Base state changed: expected \(expected), found \(actual)."
        }
    }
}
