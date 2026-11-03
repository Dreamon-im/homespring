import Foundation

public struct LayoutEditor: Sendable {
    public var state: IconState

    public init(state: IconState) {
        self.state = state
    }

    /// Applies every operation or leaves the receiver completely unchanged.
    public mutating func apply(_ operations: [LayoutOperation]) throws {
        let original = state
        var requested = Set<String>()
        do {
            let widgetSignature = try LayoutValidation.widgetSignature(state)
            for operation in operations {
                requested.formUnion(try perform(operation))
            }
            try LayoutValidation.validate(state)
            guard try LayoutValidation.widgetSignature(state) == widgetSignature else {
                throw LayoutError.widgetMoved("An operation would move or remove a widget.")
            }
            try conserveIDs(from: IconState(pages: original.pages, metrics: original.metrics), to: state)
        } catch {
            state = original
            throw error
        }
        lastRequestedIDs = requested
    }

    public func applying(_ operations: [LayoutOperation]) throws -> IconState {
        var copy = self
        try copy.apply(operations)
        return copy.state
    }

    /// IDs named by the last successful batch. Used to separate requested moves.
    private(set) var lastRequestedIDs = Set<String>()

    private mutating func perform(_ operation: LayoutOperation) throws -> Set<String> {
        switch operation {
        case .move(let id, let destination, let position):
            try move(id: id, to: destination, position: position)
            return [id]
        case .swap(let first, let second):
            try swap(first, second)
            return [first, second]
        case .createFolder(let page, let name, let ids, let position):
            try createFolder(page: page, name: name, ids: ids, position: position)
            return Set(ids)
        case .renameFolder(let from, let to):
            try renameFolder(from: from, to: to)
            return []
        case .sortFolder(let name, _):
            try sortFolder(name)
            return []
        }
    }

    private mutating func move(id: String, to destination: LayoutDestination, position: Position) throws {
        let snapshot = state
        do {
            let removed = try remove(id: id)
            if removed.kind == .unknown || removed.id == nil {
                throw LayoutError.unknownID("\(id) has no stable identifier and cannot be moved.")
            }
            if removed.kind == .widget {
                throw LayoutError.unsupportedWidget("Moving a widget is not supported.")
            }
            switch destination {
            case .dock:
                guard removed.kind != .folder else { throw LayoutError.folderInDock(removed.name) }
                try insert(removed, intoPage: 0, position: position)
            case .page(let page):
                guard state.pages.indices.contains(page), page > 0 else {
                    throw LayoutError.invalidPosition("Page \(page) does not exist.")
                }
                try insert(removed, intoPage: page, position: position)
            case .folder(let name):
                guard removed.kind != .folder else {
                    throw LayoutError.nestedFolder("Cannot put a folder into \(name).")
                }
                try insert(removed, intoFolder: name, position: position)
            }
        } catch {
            state = snapshot
            throw error
        }
    }

    private mutating func swap(_ firstID: String, _ secondID: String) throws {
        guard firstID != secondID else { return }
        guard let first = try topLevel(firstID), let second = try topLevel(secondID) else {
            throw LayoutError.invalidPosition("Swap only works for Dock and page entries, not icons inside folders.")
        }
        let firstEntry = state.pages[first.page][first.index]
        let secondEntry = state.pages[second.page][second.index]
        if first.page == 0 && secondEntry.kind == .folder {
            throw LayoutError.folderInDock(secondEntry.name)
        }
        if second.page == 0 && firstEntry.kind == .folder {
            throw LayoutError.folderInDock(firstEntry.name)
        }
        state.pages[first.page][first.index] = secondEntry
        state.pages[second.page][second.index] = firstEntry
    }

    private mutating func createFolder(page: Int, name: String, ids: [String], position: Position) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LayoutError.emptyFolder("A folder needs a non-empty name.") }
        guard !ids.isEmpty else { throw LayoutError.emptyFolder("A folder needs at least one icon.") }
        guard Set(ids).count == ids.count else { throw LayoutError.duplicateID(ids.first ?? "") }
        guard state.pages.indices.contains(page), page > 0 else {
            throw LayoutError.invalidPosition("Page \(page) does not exist.")
        }
        let existing = try LayoutStore.folderIndex(state)
        if existing[trimmed] != nil {
            throw LayoutError.malformed("A folder named \(trimmed) already exists.")
        }
        let snapshot = state
        do {
            var members: [IconEntry] = []
            for id in ids {
                let entry = try remove(id: id)
                guard entry.kind != .folder else { throw LayoutError.nestedFolder("Cannot put a folder into \(trimmed).") }
                guard entry.kind != .widget else { throw LayoutError.unsupportedWidget("Cannot put a widget into \(trimmed).") }
                members.append(entry)
            }
            let folder = IconEntry(
                fields: ["displayName": trimmed, "listType": "folder"],
                kind: .folder,
                id: nil,
                name: trimmed,
                installState: .unknown,
                folderPages: FolderPages.packed([members], size: state.metrics.folderPageSize))
            try insert(folder, intoPage: page, position: position)
        } catch {
            state = snapshot
            throw error
        }
    }

    private mutating func renameFolder(from oldName: String, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LayoutError.emptyFolder("A folder needs a non-empty name.") }
        let folders = try LayoutStore.folderIndex(state)
        guard let source = folders[oldName] else { throw LayoutError.notFound("Folder \(oldName) was not found.") }
        if oldName != trimmed, folders[trimmed] != nil {
            throw LayoutError.ambiguousFolder(trimmed)
        }
        state.pages[source.page][source.index].name = trimmed
        state.pages[source.page][source.index].fields["displayName"] = trimmed
    }

    private mutating func sortFolder(_ name: String) throws {
        let folders = try LayoutStore.folderIndex(state)
        guard let ref = folders[name] else { throw LayoutError.notFound("Folder \(name) was not found.") }
        let entries = state.pages[ref.page][ref.index].folderPages.flatMap { $0 }
        let sorted = entries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        state.pages[ref.page][ref.index].folderPages = FolderPages.packed([sorted], size: state.metrics.folderPageSize)
    }

    private mutating func insert(_ entry: IconEntry, intoPage page: Int, position: Position) throws {
        let index = try insertionIndex(in: state.pages[page], position: position, moving: entry)
        state.pages[page].insert(entry, at: index)
    }

    private mutating func insert(_ entry: IconEntry, intoFolder name: String, position: Position) throws {
        let folders = try LayoutStore.folderIndex(state)
        guard let ref = folders[name] else { throw LayoutError.notFound("Folder \(name) was not found.") }
        let pages = state.pages[ref.page][ref.index].folderPages
        let index = try insertionIndex(in: pages.flatMap { $0 }, position: position, moving: entry)
        state.pages[ref.page][ref.index].folderPages = FolderPages.inserting(
            entry, at: index, into: pages, size: state.metrics.folderPageSize)
    }

    private func insertionIndex(in entries: [IconEntry], position: Position, moving: IconEntry) throws -> Int {
        switch position {
        case .end:
            return entries.count
        case .start:
            return 0
        case .index(let index):
            guard (0...entries.count).contains(index) else {
                throw LayoutError.invalidPosition("Index \(index) is outside 0...\(entries.count).")
            }
            return index
        case .before(let id), .after(let id):
            guard let anchor = entries.firstIndex(where: { $0.id == id }) else {
                throw LayoutError.notFound("Position anchor \(id) was not found in the destination.")
            }
            return position == .before(id: id) ? anchor : anchor + 1
        case .sorted:
            guard !entries.contains(where: { $0.kind == .widget }) else {
                throw LayoutError.unsupportedWidget("Sorted insertion cannot pass a widget without moving it.")
            }
            let index = entries.firstIndex {
                moving.name.localizedCaseInsensitiveCompare($0.name) == .orderedAscending
            }
            return index ?? entries.count
        }
    }

    private mutating func remove(id: String) throws -> IconEntry {
        if let top = try topLevel(id) {
            return state.pages[top.page].remove(at: top.index)
        }
        let folders = try LayoutStore.folderIndex(state)
        for (_, ref) in folders {
            let pages = state.pages[ref.page][ref.index].folderPages
            for (pageIndex, page) in pages.enumerated() {
                guard let index = page.firstIndex(where: { $0.id == id }) else { continue }
                let total = pages.flatMap { $0 }.count
                guard total > 1 else {
                    throw LayoutError.emptyFolder("Removing \(id) would leave its folder empty.")
                }
                let result = FolderPages.removing(at: index, onPage: pageIndex, from: pages)
                state.pages[ref.page][ref.index].folderPages = result.pages
                return result.entry
            }
        }
        throw LayoutError.notFound("\(id) was not found.")
    }

    private func topLevel(_ id: String) throws -> PageRef? {
        for (page, entries) in state.pages.enumerated() {
            if let index = entries.firstIndex(where: { $0.id == id }) {
                return PageRef(page: page, index: index)
            }
        }
        return nil
    }
}
