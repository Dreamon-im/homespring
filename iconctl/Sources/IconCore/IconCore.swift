import Foundation

public enum IconCore {
    public static let version = "0.2.0"

    public static func load(
        _ raw: [Any],
        metrics: GridMetrics = GridMetrics(),
        options: LayoutOptions = LayoutOptions()
    ) throws -> IconState {
        try LayoutStore.load(raw, metrics: metrics, options: options)
    }

    public static func encode(_ state: IconState) -> [Any] {
        LayoutStore.encode(state)
    }

    public static func stateHash(_ state: IconState) throws -> String {
        try LayoutStore.stateHash(state)
    }

    public static func requireBaseHash(_ expected: String, matches state: IconState) throws {
        try LayoutStore.requireBaseHash(expected, matches: state)
    }

    public static func inventory(_ state: IconState) throws -> [InventoryItem] {
        try LayoutQuery.inventory(state)
    }

    public static func find(_ query: String, in state: IconState) throws -> [InventoryItem] {
        try LayoutQuery.find(query, in: state)
    }

    public static func render(_ state: IconState) throws -> String {
        try LayoutQuery.render(state)
    }

    public static func apply(_ batch: LayoutBatch, to state: IconState) throws -> (state: IconState, diff: LayoutDiff) {
        try apply(batch.operations, to: state, expectedBaseHash: batch.expectedBaseHash)
    }

    public static func apply(
        _ operations: [LayoutOperation],
        to state: IconState,
        expectedBaseHash: String? = nil
    ) throws -> (state: IconState, diff: LayoutDiff) {
        if let expectedBaseHash {
            try requireBaseHash(expectedBaseHash, matches: state)
        }
        let before = state
        var editor = LayoutEditor(state: state)
        try editor.apply(operations)
        try LayoutValidation.widgetStability(editor.state, before: before)
        try conserveIDs(from: before, to: editor.state)
        let diff = try LayoutQuery.diff(from: before, to: editor.state, requestedIDs: editor.lastRequestedIDs)
        return (editor.state, diff)
    }
}

extension LayoutEditor {
    /// Exposes the IDs explicitly named by a completed batch for diffing.
    public var requestedIDs: Set<String> { lastRequestedIDs }
}

func conserveIDs(from original: IconState, to edited: IconState) throws {
    let source = try identifiableIDs(original)
    let result = try identifiableIDs(edited)
    if let missing = source.subtracting(result).sorted().first {
        throw LayoutError.unknownID("\(missing) would leave the home screen.")
    }
    if let added = result.subtracting(source).sorted().first {
        throw LayoutError.unknownID("\(added) is not already on the home screen.")
    }
}

private func identifiableIDs(_ state: IconState) throws -> Set<String> {
    var ids = Set<String>()
    func visit(_ entry: IconEntry) throws {
        if let id = entry.id {
            guard ids.insert(id).inserted else { throw LayoutError.duplicateID(id) }
        }
        for page in entry.folderPages {
            for child in page { try visit(child) }
        }
    }
    for page in state.pages {
        for entry in page { try visit(entry) }
    }
    return ids
}
