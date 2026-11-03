import Foundation
import IconCore
import Testing

private let snapshotURL = URL(fileURLWithPath: "/tmp/ios-home-screen-m1.3WPsRN/iconctl-raw.plist")
private let legacyJSONURL = URL(
    fileURLWithPath: "/Users/airbob/.cache/uv/archive-v0/AnC2eSY2C1n6GaiYSpUK3/lib/python3.12/site-packages/workspace/backups/raw-20261026223239837.json")

private func loadSnapshot() throws -> IconState {
    let data = try Data(contentsOf: snapshotURL)
    let raw = try PropertyListSerialization.propertyList(from: data, format: nil) as! [Any]
    return try IconCore.load(raw, metrics: GridMetrics(rows: 6, cols: 4, dockMax: 4))
}

private func loadLegacyJSON() throws -> IconState {
    let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyJSONURL)) as! [Any]
    return try IconCore.load(raw)
}

private func app(_ id: String, name: String, version: String = "1", date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> [String: Any] {
    [
        "bundleIdentifier": id,
        "displayIdentifier": id,
        "displayName": name,
        "bundleVersion": version,
        "iconModDate": date,
        "futureField": Data([1, 2, 3]),
    ]
}

private func offloaded(_ id: String, name: String) -> [String: Any] {
    ["displayIdentifier": id, "displayName": name]
}

private func webclip(id: String, name: String, url: String) -> [String: Any] {
    ["displayIdentifier": id, "displayName": name, "webClipURL": url, "iconModDate": Date(timeIntervalSince1970: 1_800_000_000)]
}

private func widget(size: String, id: String = "widget.one") -> [String: Any] {
    [
        "elementType": "widget",
        "gridSize": size,
        "widgetIdentifier": id,
        "displayName": "Weather",
        "containerBundleIdentifier": "com.apple.weather",
        "unknownWidgetField": 7,
    ]
}

private func smartStack(size: String) -> [String: Any] {
    [
        "iconType": "custom",
        "gridSize": size,
        "displayIdentifier": "STACK-ONE",
        "allowsSuggestions": true,
        "iconLists": [Any](),
        "elements": [widget(size: size, id: "widget.one"), widget(size: size, id: "widget.two")],
    ]
}

private func state(_ pages: [[Any]], metrics: GridMetrics = GridMetrics(rows: 2, cols: 2, dockMax: 2)) throws -> IconState {
    try IconCore.load([[app("dock.app", name: "Dock")]] + pages, metrics: metrics)
}

@Test func versionIsSet() {
    #expect(IconCore.version == "0.2.0")
}

@Test func realSnapshotPreservesDatesAndClassifiesEntries() throws {
    let originalData = try Data(contentsOf: snapshotURL)
    let original = try PropertyListSerialization.propertyList(from: originalData, format: nil) as! [Any]
    let state = try IconCore.load(original, metrics: GridMetrics(rows: 6, cols: 4, dockMax: 4))
    let encoded = IconCore.encode(state)
    let roundTrip = try PropertyListSerialization.data(fromPropertyList: encoded, format: .binary, options: 0)
    let decoded = try PropertyListSerialization.propertyList(from: roundTrip, format: nil) as! [Any]
    #expect(plistEqual(original, decoded))

    let inventory = try IconCore.inventory(state)
    #expect(inventory.contains { $0.installState == .offloaded })
    #expect(inventory.contains { $0.kind == .webclip && $0.id == "44B2715EBE794B79886802D1467D9F9D" })
    let connects = inventory.filter { $0.name == "Connect" }
    #expect(connects.count == 2)
    #expect(Set(connects.compactMap(\.id)).count == 2)
    let rendered = try IconCore.render(state)
    #expect(rendered.contains("Dock"))
    #expect(rendered.contains("Page 1"))
}

@Test func legacyJSONRecognizesDuplicateNames() throws {
    let state = try loadLegacyJSON()
    let found = try IconCore.inventory(state).filter { $0.name == "Connect" }
    #expect(found.compactMap(\.id).sorted() == ["com.apple.AppStoreConnect", "com.apple.ist.AppleConnect"])
    #expect(found.allSatisfy { $0.installState == .installed })
    let fuzzy = try IconCore.find("Connect", in: state)
    #expect(fuzzy.count >= 2)
    let offloaded = try IconCore.inventory(state).filter { $0.installState == .offloaded }
    #expect(offloaded.count > 100)
}

@Test func duplicateWebClipURLsStayDistinct() throws {
    let shared = "https://example.com/same"
    let loaded = try state([
        [webclip(id: "CLIP-ONE", name: "One", url: shared), webclip(id: "CLIP-TWO", name: "Two", url: shared)],
    ])
    let result = try IconCore.apply([
        .move(id: "CLIP-TWO", to: .page(1), position: .start),
    ], to: loaded).state
    let clips = try IconCore.inventory(result).filter { $0.kind == .webclip }
    #expect(clips.map(\.id) == ["CLIP-TWO", "CLIP-ONE"])
    #expect(clips.allSatisfy { $0.webClipURL == shared })
}

@Test func unknownAndOffloadedEntriesAreClassifiedConservatively() throws {
    let loaded = try state([
        [offloaded("gone.app", name: "Gone"), ["displayName": "Mystery"], app("kept.app", name: "Kept")],
    ])
    let inventory = try IconCore.inventory(loaded)
    #expect(inventory.first { $0.name == "Gone" }?.installState == .offloaded)
    #expect(inventory.first { $0.name == "Mystery" }?.installState == .unknown)
    #expect(throws: LayoutError.self) {
        try IconCore.apply([.move(id: "not-an-id", to: .dock)], to: loaded)
    }
}

@Test func folderOverflowPaginatesAndRefusesAmbiguousNames() throws {
    let ids = (1...10).map { "app.\($0)" }
    let loaded = try state([ids.map { app($0, name: "App \($0)") }], metrics: GridMetrics(rows: 6, cols: 4, dockMax: 4), optionsPageSize: 9)
    let created = try IconCore.apply([
        .createFolder(page: 1, name: "Overflow", ids: ids),
    ], to: loaded).state
    let folder = created.pages[1].first { $0.kind == .folder }
    #expect(folder?.folderPages.map(\.count) == [9, 1])
    let again = try IconCore.apply([
        .createFolder(page: 1, name: "Second", ids: ["app.1"]),
    ], to: loaded).state
    var duplicated = IconCore.encode(again)
    var page = duplicated[1] as! [Any]
    page.append(page.last!)
    duplicated[1] = page
    let ambiguous = try IconCore.load(duplicated)
    #expect(throws: LayoutError.ambiguousFolder("Second")) {
        try IconCore.apply([.renameFolder(from: "Second", to: "Elsewhere")], to: ambiguous)
    }
}

@Test func positionsBeforeAfterSortedAndIndex() throws {
    let loaded = try state([
        [app("a", name: "Charlie"), app("b", name: "Alpha"), app("c", name: "Bravo")],
    ])
    let moved = try IconCore.apply([
        .move(id: "c", to: .page(1), position: .before(id: "a")),
        .move(id: "b", to: .page(1), position: .after(id: "c")),
    ], to: loaded).state
    #expect(moved.pages[1].compactMap(\.id) == ["c", "b", "a"])

    let indexed = try IconCore.apply([
        .move(id: "a", to: .page(1), position: .index(2)),
    ], to: loaded).state
    #expect(indexed.pages[1].compactMap(\.id) == ["b", "c", "a"])

    let sorted = try IconCore.apply([
        .move(id: "a", to: .folder(name: "Names"), position: .sorted),
    ], to: try IconCore.apply([
        .createFolder(page: 1, name: "Names", ids: ["b", "c"]),
    ], to: loaded).state).state
    let names = sorted.pages[1].first { $0.name == "Names" }?.folderPages.flatMap { $0 }.map(\.name)
    #expect(names == ["Alpha", "Bravo", "Charlie"])
}

@Test func sortFolderAndSwapKeepUnrequestedFields() throws {
    let date = Date(timeIntervalSince1970: 1_234_567)
    let loaded = try IconCore.load([
        [app("dock.app", name: "Dock")],
        [app("b", name: "Beta", date: date), app("a", name: "Alpha", date: date)],
    ])
    let sorted = try IconCore.apply([
        .createFolder(page: 1, name: "Letters", ids: ["b", "a"]),
        .sortFolder(name: "Letters"),
    ], to: loaded).state
    let children = sorted.pages[1][0].folderPages.flatMap { $0 }
    #expect(children.map(\.name) == ["Alpha", "Beta"])
    #expect(children[0].fields["iconModDate"] as? Date == date)
    #expect(children[0].fields["futureField"] as? Data == Data([1, 2, 3]))

    let swapped = try IconCore.apply([.swap("b", "a")], to: loaded).state
    #expect(swapped.pages[1].compactMap(\.id) == ["a", "b"])
}

@Test func failingBatchLeavesInputUnchanged() throws {
    let loaded = try state([[app("a", name: "Alpha"), app("b", name: "Beta")]])
    let before = IconCore.encode(loaded)
    #expect(throws: LayoutError.self) {
        try IconCore.apply([
            .move(id: "a", to: .dock),
            .move(id: "missing", to: .page(1)),
        ], to: loaded)
    }
    #expect(plistEqual(before, IconCore.encode(loaded)))
}

@Test func widgetMovementAndCapacityAreRefused() throws {
    let loaded = try IconCore.load([
        [app("dock.app", name: "Dock")],
        [widget(size: "small"), app("a", name: "Alpha"), app("b", name: "Beta")],
    ], metrics: GridMetrics(rows: 2, cols: 2, dockMax: 2))
    let before = IconCore.encode(loaded)
    #expect(throws: LayoutError.self) {
        try IconCore.apply([.move(id: "a", to: .page(1), position: .start)], to: loaded)
    }
    #expect(throws: LayoutError.self) {
        try IconCore.apply([.move(id: "dock.app", to: .page(1), position: .end)], to: loaded)
    }
    #expect(plistEqual(before, IconCore.encode(loaded)))
    #expect(throws: LayoutError.self) {
        try IconCore.load([
            [app("dock.app", name: "Dock")],
            [widget(size: "giant"), app("a", name: "Alpha")],
        ])
    }
}

private func folder(_ name: String, _ pages: [[String]]) -> [String: Any] {
    [
        "listType": "folder",
        "displayName": name,
        "iconLists": pages.map { page in page.map { app($0, name: $0) } },
    ]
}

private func folderPageIDs(_ state: IconState, _ name: String) -> [[String]] {
    let entry = state.pages.dropFirst().joined().first { $0.kind == .folder && $0.name == name }
    return entry?.folderPages.map { $0.compactMap(\.id) } ?? []
}

@Test func movingOutOfAFolderOnlyTouchesItsPage() throws {
    // Uneven pages, as on a real phone: removing one app must not repack the rest.
    let loaded = try state([[
        folder("Hide", [["a1", "a2", "a3"], ["b1", "b2"], ["c1", "c2", "c3", "c4"]]),
        folder("Keep", [["k1"]]),
    ]], metrics: GridMetrics(rows: 6, cols: 4, dockMax: 4))
    let result = try IconCore.apply([.move(id: "b1", to: .folder(name: "Keep"), position: .end)], to: loaded)
    #expect(folderPageIDs(result.state, "Hide") == [["a1", "a2", "a3"], ["b2"], ["c1", "c2", "c3", "c4"]])
    #expect(folderPageIDs(result.state, "Keep") == [["k1", "b1"]])
    #expect(result.diff.requested.map(\.id) == ["b1"])
    #expect(result.diff.incidental.map(\.id) == ["b2"])

    // Removing the only app on a page drops that page and leaves the others alone.
    let emptied = try IconCore.apply([.move(id: "b2", to: .page(1), position: .end)], to: result.state).state
    #expect(folderPageIDs(emptied, "Hide") == [["a1", "a2", "a3"], ["c1", "c2", "c3", "c4"]])
}

@Test func insertingIntoAFullFolderPageCarriesOverOnlyAsFarAsNeeded() throws {
    let full = (1...9).map { "f\($0)" }
    let loaded = try state([[
        folder("Box", [full, (1...9).map { "g\($0)" }, ["h1"]]),
        app("new", name: "New"),
    ]], metrics: GridMetrics(rows: 6, cols: 4, dockMax: 4))
    // Into the middle of a full first page: f9 carries to page 2, g9 to page 3.
    let middle = try IconCore.apply([.move(id: "new", to: .folder(name: "Box"), position: .index(1))], to: loaded).state
    #expect(folderPageIDs(middle, "Box") == [
        ["f1", "new"] + (2...8).map { "f\($0)" },
        ["f9"] + (1...8).map { "g\($0)" },
        ["g9", "h1"],
    ])
    // At the end: joins the last page, which has room; nothing else moves.
    let end = try IconCore.apply([.move(id: "new", to: .folder(name: "Box"), position: .end)], to: loaded).state
    #expect(folderPageIDs(end, "Box") == [full, (1...9).map { "g\($0)" }, ["h1", "new"]])
    // At the end of a folder whose last page is full: starts a new page.
    let single = try state([[folder("One", [full]), app("new", name: "New")]], metrics: GridMetrics(rows: 6, cols: 4, dockMax: 4))
    let appended = try IconCore.apply([.move(id: "new", to: .folder(name: "One"), position: .end)], to: single).state
    #expect(folderPageIDs(appended, "One") == [full, ["new"]])
}

@Test func smartStackIsAWidgetNotAnEmptyFolder() throws {
    let raw: [Any] = [
        [app("dock.app", name: "Dock")],
        [smartStack(size: "small"), app("a", name: "Alpha")],
        [app("b", name: "Beta")],
    ]
    let loaded = try IconCore.load(raw, metrics: GridMetrics(rows: 6, cols: 4, dockMax: 4))
    let stack = loaded.pages[1][0]
    #expect(stack.kind == .widget)
    #expect(stack.name == "Smart Stack")
    #expect(try stack.gridSpan() == (2, 2))
    #expect(plistEqual(raw, IconCore.encode(loaded)))

    let moved = try IconCore.apply([.move(id: "b", to: .page(1), position: .end)], to: loaded).state
    #expect(moved.pages[1].compactMap(\.id) == ["a", "b"])
    #expect(plistEqual(moved.pages[1][0].fields, stack.fields))

    var folderish = smartStack(size: "small")
    folderish["iconLists"] = [[app("c", name: "Gamma")]]
    #expect(throws: LayoutError.self) {
        try IconCore.load([[app("dock.app", name: "Dock")], [folderish]])
    }
}

@Test func diffSeparatesRequestedAndIncidentalMoves() throws {
    let loaded = try state([[app("a", name: "Alpha"), app("b", name: "Beta"), app("c", name: "Gamma")]])
    let result = try IconCore.apply([.move(id: "c", to: .page(1), position: .start)], to: loaded)
    #expect(result.diff.requested.map(\.id) == ["c"])
    #expect(result.diff.incidental.map(\.id).contains("a"))
    #expect(result.diff.removed.isEmpty)
}

@Test func hashIgnoresDictionaryOrderAndDetectsStaleBase() throws {
    let first = try state([[app("a", name: "Alpha")]])
    var reversed = IconCore.encode(first)
    let page = reversed[1] as! [[String: Any]]
    reversed[1] = page.map { entry in
        Dictionary(uniqueKeysWithValues: entry.sorted { $0.key > $1.key })
    }
    let second = try IconCore.load(reversed, metrics: first.metrics)
    let hash = try IconCore.stateHash(first)
    #expect(try IconCore.stateHash(second) == hash)
    try IconCore.requireBaseHash(hash, matches: second)
    let changed = try IconCore.apply([.move(id: "a", to: .dock)], to: first).state
    #expect(throws: LayoutError.self) {
        try IconCore.apply([.move(id: "a", to: .page(1))], to: changed, expectedBaseHash: hash)
    }
}

private func state(_ pages: [[Any]], metrics: GridMetrics, optionsPageSize: Int) throws -> IconState {
    try IconCore.load([[app("dock.app", name: "Dock")]] + pages, metrics: metrics, options: LayoutOptions(folderPageSize: optionsPageSize))
}

private func plistEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    switch (lhs, rhs) {
    case let (left as NSNumber, right as NSNumber): return left == right
    case let (left as String, right as String): return left == right
    case let (left as Date, right as Date): return left == right
    case let (left as Data, right as Data): return left == right
    case let (left as [Any], right as [Any]):
        return left.count == right.count && zip(left, right).allSatisfy(plistEqual)
    case let (left as [String: Any], right as [String: Any]):
        return left.count == right.count && left.keys.allSatisfy { plistEqual(left[$0]!, right[$0] as Any) }
    default: return false
    }
}
