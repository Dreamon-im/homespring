import Foundation

public enum LayoutQuery {
    public static func inventory(_ state: IconState) throws -> [InventoryItem] {
        var items: [InventoryItem] = []
        for (pageNumber, page) in state.pages.enumerated() {
            let positions = try LayoutPlacement.positions(on: page, metrics: state.metrics)
            for (index, entry) in page.enumerated() {
                let cell = positions[index]
                let container: IconLocation.Container = pageNumber == 0 ? .dock : .page(pageNumber)
                items.append(item(entry, at: IconLocation(
                    container: container, index: index, row: cell?.row, col: cell?.col)))
                guard entry.kind == .folder else { continue }
                for (folderPage, children) in entry.folderPages.enumerated() {
                    for (childIndex, child) in children.enumerated() {
                        let columns = max(1, Int(Double(state.metrics.folderPageSize).squareRoot()))
                        let row = childIndex / columns + 1
                        let col = childIndex % columns + 1
                        items.append(item(child, at: IconLocation(
                            container: .folder(name: entry.name, page: pageNumber, folderPage: folderPage + 1),
                            index: childIndex,
                            row: row,
                            col: col)))
                    }
                }
            }
        }
        return items
    }

    public static func find(_ query: String, in state: IconState) throws -> [InventoryItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return try inventory(state).filter { item in
            item.name.localizedCaseInsensitiveContains(needle)
                || item.id?.localizedCaseInsensitiveContains(needle) == true
                || item.webClipURL?.localizedCaseInsensitiveContains(needle) == true
        }
    }

    public static func render(_ state: IconState) throws -> String {
        var blocks: [String] = []
        for (number, page) in state.pages.enumerated() {
            var cells = Array(
                repeating: Array<String?>(repeating: nil, count: state.metrics.cols),
                count: state.metrics.rows)
            let positions = try LayoutPlacement.positions(on: page, metrics: state.metrics)
            for (entry, position) in zip(page, positions) {
                guard let position else { continue }
                let span = try entry.gridSpan()
                let row = position.row - 1
                let col = position.col - 1
                cells[row][col] = label(entry)
                for dy in 0..<span.height {
                    for dx in 0..<span.width where dy != 0 || dx != 0 {
                        cells[row + dy][col + dx] = "‖"
                    }
                }
            }
            var lines = [number == 0 ? "Dock" : "Page \(number)"]
            for (row, values) in cells.enumerated() {
                let rendered = values.map { value in (value ?? "·").prefix(12).padding(toLength: 12, withPad: " ", startingAt: 0) }
                lines.append("  R\(row + 1): \(rendered.joined(separator: " | "))")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    public static func diff(from original: IconState, to edited: IconState, requestedIDs: Set<String>) throws -> LayoutDiff {
        let before = try Dictionary(uniqueKeysWithValues: inventory(original).compactMap { item in
            item.id.map { ($0, item) }
        })
        let after = try Dictionary(uniqueKeysWithValues: inventory(edited).compactMap { item in
            item.id.map { ($0, item) }
        })
        var requested: [EntryChange] = []
        var incidental: [EntryChange] = []
        var removed: [EntryChange] = []
        for (id, source) in before.sorted(by: { $0.key < $1.key }) {
            guard let destination = after[id] else {
                removed.append(EntryChange(id: id, name: source.name, from: source.location))
                continue
            }
            guard source.location != destination.location else { continue }
            let change = EntryChange(id: id, name: source.name, from: source.location, to: destination.location)
            if requestedIDs.contains(id) {
                requested.append(change)
            } else {
                incidental.append(change)
            }
        }
        return LayoutDiff(requested: requested, incidental: incidental, removed: removed)
    }

    private static func item(_ entry: IconEntry, at location: IconLocation) -> InventoryItem {
        InventoryItem(
            id: entry.id,
            name: entry.name,
            kind: entry.kind,
            installState: entry.installState,
            location: location,
            webClipURL: entry.webClipURL,
            bundleVersion: entry.bundleVersion)
    }

    private static func label(_ entry: IconEntry) -> String {
        switch entry.kind {
        case .widget:
            let size = (entry.fields["gridSize"] as? String) ?? "?"
            return "\(entry.name)·\(size)"
        case .folder:
            let count = entry.folderPages.flatMap { $0 }.count
            return "[\(entry.name)]×\(count)"
        default:
            return entry.name.isEmpty ? (entry.id ?? "?") : entry.name
        }
    }
}
