import Foundation

enum LayoutValidation {
    static func validate(_ state: IconState) throws {
        var seen = Set<String>()
        func visit(_ entry: IconEntry, dock: Bool) throws {
            if entry.kind == .widget, dock {
                throw LayoutError.unsupportedWidget("A widget in the Dock is not supported.")
            }
            if let id = entry.id {
                guard seen.insert(id).inserted else { throw LayoutError.duplicateID(id) }
            } else if entry.kind != .folder && entry.kind != .widget {
                throw LayoutError.unknownID("An entry named \(entry.name) has no stable identifier.")
            }
            if entry.kind == .folder {
                if dock { throw LayoutError.folderInDock(entry.name) }
                let children = entry.folderPages.flatMap { $0 }
                if children.isEmpty { throw LayoutError.emptyFolder("Folder \(entry.name) is empty.") }
                if entry.folderPages.contains(where: { $0.count > state.metrics.folderPageSize || $0.isEmpty }) {
                    throw LayoutError.capacity("Folder \(entry.name) has an invalid page.")
                }
                for child in children {
                    if child.kind == .folder { throw LayoutError.nestedFolder(entry.name) }
                    if child.kind == .widget {
                        throw LayoutError.unsupportedWidget("A widget inside \(entry.name) is not supported.")
                    }
                    try visit(child, dock: false)
                }
            }
        }
        if state.pages.isEmpty { throw LayoutError.malformed("The icon state has no Dock.") }
        if state.pages[0].count > state.metrics.dockMax {
            throw LayoutError.capacity("The Dock has \(state.pages[0].count) icons; its maximum is \(state.metrics.dockMax).")
        }
        for (number, page) in state.pages.enumerated() {
            for entry in page { try visit(entry, dock: number == 0) }
            if number > 0, try LayoutPlacement.overflows(page, metrics: state.metrics) {
                throw LayoutError.capacity("Page \(number) exceeds the \(state.metrics.cols)x\(state.metrics.rows) grid.")
            }
        }
    }

    /// Compares widget order and estimated cells with the pre-edit state when supplied.
    static func widgetStability(_ state: IconState, before: IconState? = nil) throws {
        let current = try widgetSignature(state)
        guard let before else { return }
        let original = try widgetSignature(before)
        guard current == original else {
            throw LayoutError.widgetMoved("An operation would move or remove a widget.")
        }
    }

    static func widgetSignature(_ state: IconState) throws -> [String] {
        try state.pages.enumerated().flatMap { pageNumber, page in
            let positions = try LayoutPlacement.positions(on: page, metrics: state.metrics)
            return zip(page, positions).compactMap { entry, position -> String? in
                guard entry.kind == .widget else { return nil }
                let row = position?.row ?? -1
                let col = position?.col ?? -1
                let identity = [
                    entry.fields["widgetIdentifier"] as? String,
                    entry.fields["displayIdentifier"] as? String,
                    entry.fields["containerBundleIdentifier"] as? String,
                    entry.name,
                ].compactMap { $0 }.joined(separator: "/")
                return "\(pageNumber):\(row),\(col):\(identity)"
            }
        }
    }
}
