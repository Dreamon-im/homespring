import Foundation
import IconCore

struct LayoutPlan: Codable {
    var baseHash: String
    var resultHash: String
    var operations: [LayoutOperation]
    var diff: DiffJSON
}

enum OperationJSON {
    static func decode(_ data: Data) throws -> [LayoutOperation] {
        try JSONDecoder().decode([LayoutOperation].self, from: data)
    }
}

extension LayoutPlan {
    static func encode(_ plan: LayoutPlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(plan)
    }
}

extension LayoutOperation: Codable {
    private enum Kind: String, Codable { case move, swap, createFolder, renameFolder, sortFolder }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .op) {
        case .move:
            self = .move(
                id: try container.decode(String.self, forKey: .id),
                to: try container.decode(LayoutDestination.self, forKey: .to),
                position: try container.decodeIfPresent(Position.self, forKey: .position) ?? .end)
        case .swap:
            self = .swap(try container.decode(String.self, forKey: .a), try container.decode(String.self, forKey: .b))
        case .createFolder:
            self = .createFolder(
                page: try container.decode(Int.self, forKey: .page),
                name: try container.decode(String.self, forKey: .name),
                ids: try container.decode([String].self, forKey: .ids),
                position: try container.decodeIfPresent(Position.self, forKey: .position) ?? .end)
        case .renameFolder:
            self = .renameFolder(from: try container.decode(String.self, forKey: .from), to: try container.decode(String.self, forKey: .to))
        case .sortFolder:
            self = .sortFolder(name: try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .move(let id, let destination, let position):
            try container.encode(Kind.move, forKey: .op)
            try container.encode(id, forKey: .id)
            try container.encode(destination, forKey: .to)
            try container.encode(position, forKey: .position)
        case .swap(let a, let b):
            try container.encode(Kind.swap, forKey: .op)
            try container.encode(a, forKey: .a)
            try container.encode(b, forKey: .b)
        case .createFolder(let page, let name, let ids, let position):
            try container.encode(Kind.createFolder, forKey: .op)
            try container.encode(page, forKey: .page)
            try container.encode(name, forKey: .name)
            try container.encode(ids, forKey: .ids)
            try container.encode(position, forKey: .position)
        case .renameFolder(let from, let to):
            try container.encode(Kind.renameFolder, forKey: .op)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .sortFolder(let name, _):
            try container.encode(Kind.sortFolder, forKey: .op)
            try container.encode(name, forKey: .name)
        }
    }

    private enum CodingKeys: String, CodingKey { case op, id, to, position, a, b, page, name, ids, from }
}

extension LayoutDestination: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "dock" { self = .dock; return }
        if value.hasPrefix("page:"), let page = Int(value.dropFirst(5)), page > 0 { self = .page(page); return }
        if value.hasPrefix("folder:") {
            let name = String(value.dropFirst(7))
            guard !name.isEmpty else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Folder name is empty.")) }
            self = .folder(name: name)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected dock, page:N, or folder:Name."))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .dock: try container.encode("dock")
        case .page(let page): try container.encode("page:\(page)")
        case .folder(let name): try container.encode("folder:\(name)")
        }
    }
}

extension Position: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "end": self = .end
        case "start": self = .start
        case "sorted": self = .sorted
        default:
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw Self.invalid(value, decoder) }
            switch parts[0] {
            case "before": self = .before(id: parts[1])
            case "after": self = .after(id: parts[1])
            case "index":
                guard let index = Int(parts[1]), index >= 0 else { throw Self.invalid(value, decoder) }
                self = .index(index)
            default: throw Self.invalid(value, decoder)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .end: try container.encode("end")
        case .start: try container.encode("start")
        case .sorted: try container.encode("sorted")
        case .before(let id): try container.encode("before:\(id)")
        case .after(let id): try container.encode("after:\(id)")
        case .index(let index): try container.encode("index:\(index)")
        }
    }

    private static func invalid(_ value: String, _ decoder: Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid position \(value)."))
    }
}

struct LocationJSON: Codable {
    var container: String
    var index: Int
    var row: Int?
    var col: Int?

    init(_ location: IconLocation) {
        switch location.container {
        case .dock: container = "dock"
        case .page(let page): container = "page:\(page)"
        case .folder(let name, let page, let folderPage):
            container = "folder:\(name)@page:\(page)/folderPage:\(folderPage)"
        }
        index = location.index
        row = location.row
        col = location.col
    }
}

struct ChangeJSON: Codable {
    var id: String
    var name: String
    var from: LocationJSON?
    var to: LocationJSON?

    init(_ change: EntryChange) {
        id = change.id
        name = change.name
        from = change.from.map(LocationJSON.init)
        to = change.to.map(LocationJSON.init)
    }
}

struct DiffJSON: Codable {
    var requested: [ChangeJSON]
    var incidental: [ChangeJSON]
    var removed: [ChangeJSON]
}

extension LayoutDiff {
    var jsonValue: DiffJSON {
        DiffJSON(
            requested: requested.map(ChangeJSON.init),
            incidental: incidental.map(ChangeJSON.init),
            removed: removed.map(ChangeJSON.init))
    }
}

