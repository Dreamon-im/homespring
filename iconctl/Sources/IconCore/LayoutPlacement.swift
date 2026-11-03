import Foundation

struct PlacedCell: Equatable {
    var row: Int
    var col: Int
}

enum LayoutPlacement {
    static func positions(on page: [IconEntry], metrics: GridMetrics) throws -> [PlacedCell?] {
        var occupied = Array(repeating: Array(repeating: false, count: metrics.cols), count: metrics.rows)
        return try page.map { entry in
            let span = try entry.gridSpan()
            return place(span, in: &occupied, metrics: metrics)
        }
    }

    static func overflows(_ page: [IconEntry], metrics: GridMetrics) throws -> Bool {
        try positions(on: page, metrics: metrics).contains(nil)
    }

    private static func place(
        _ span: (width: Int, height: Int),
        in occupied: inout [[Bool]],
        metrics: GridMetrics
    ) -> PlacedCell? {
        guard span.width <= metrics.cols, span.height <= metrics.rows else { return nil }
        for row in 0...(metrics.rows - span.height) {
            for col in 0...(metrics.cols - span.width) {
                let fits = (0..<span.height).allSatisfy { dy in
                    (0..<span.width).allSatisfy { dx in !occupied[row + dy][col + dx] }
                }
                guard fits else { continue }
                for dy in 0..<span.height {
                    for dx in 0..<span.width { occupied[row + dy][col + dx] = true }
                }
                return PlacedCell(row: row + 1, col: col + 1)
            }
        }
        return nil
    }
}

enum FolderPages {
    /// Inserts `entry` at a flat index across all folder pages, changing as little
    /// as possible: it goes into the page that index falls in, and only when that
    /// page is full does its last entry carry over to the next page, stopping at
    /// the first page with room. Pages after that keep their exact layout.
    static func inserting(_ entry: IconEntry, at flatIndex: Int, into pages: [[IconEntry]], size: Int) -> [[IconEntry]] {
        var pages = pages.filter { !$0.isEmpty }
        guard !pages.isEmpty else { return [[entry]] }
        var page = pages.count - 1
        var offset = pages[page].count
        var start = 0
        for (index, entries) in pages.enumerated() {
            // An index at a page boundary goes on the earlier page when it has
            // room, otherwise at the start of the next one.
            if flatIndex < start + entries.count || (flatIndex == start + entries.count && entries.count < size) {
                page = index
                offset = flatIndex - start
                break
            }
            start += entries.count
        }
        if offset == pages[page].count, pages[page].count >= size {
            // Appending to a full page: start the next page instead.
            page += 1
            offset = 0
            if page == pages.count { pages.append([]) }
        }
        pages[page].insert(entry, at: offset)
        while pages[page].count > size {
            let overflow = pages[page].removeLast()
            page += 1
            if page == pages.count { pages.append([]) }
            pages[page].insert(overflow, at: 0)
        }
        return pages
    }

    /// Removes the entry at `index` on `page`, leaving every other page as it is.
    /// A page left empty is dropped.
    static func removing(at index: Int, onPage page: Int, from pages: [[IconEntry]]) -> (entry: IconEntry, pages: [[IconEntry]]) {
        var pages = pages
        let entry = pages[page].remove(at: index)
        if pages[page].isEmpty { pages.remove(at: page) }
        return (entry, pages)
    }

    static func packed(_ pages: [[IconEntry]], size: Int) -> [[IconEntry]] {
        let entries = pages.flatMap { $0 }
        guard !entries.isEmpty else { return [] }
        return stride(from: 0, to: entries.count, by: size).map { start in
            Array(entries[start..<min(start + size, entries.count)])
        }
    }
}
