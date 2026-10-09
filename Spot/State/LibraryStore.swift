//
//  LibraryStore.swift
//  Spot
//

import Foundation
import Observation
import SpotCore
import SwiftData

enum LibraryEntryKind: CustomStringConvertible {
    case scale
    case chord
    case interval

    var description: String {
        switch self {
        case .scale: return "Scale"
        case .chord: return "Chord"
        case .interval: return "Interval"
        }
    }
}

enum LibrarySortOrder {
    /// Scales, chords and intervals in the order they are defined (related items together).
    case library
    case name
}

/// Where a library item came from.
enum LibrarySource: Hashable, CustomStringConvertible {
    case builtIn
    case mine
    case imported(String)

    var description: String {
        switch self {
        case .builtIn: return "Built-in"
        case .mine: return "Mine"
        case .imported(let name): return name
        }
    }
}

/// What to put in an exported `.spotlib` file.
enum LibraryExportScope: Hashable {
    /// Your own and imported items, with your shapes.
    case mine
    case tag(String)
    case everything
}

/// A row in the library list.
struct LibraryEntry: Identifiable, Hashable, Searchable {
    let id: String
    let name: String
    let kind: LibraryEntryKind
    let detail: String
    let family: String?
    let source: LibrarySource
    let searchTerms: [String]

    var properties: [FuseProp] {
        searchTerms.map { FuseProp($0) }
    }

    var isEditable: Bool {
        source != .builtIn && kind != .interval
    }
}

@Observable
final class LibraryStore {
    let builtIn: LibraryBundle

    /// Built-in followed by user definitions.
    private(set) var scales: [ScaleDefinition] = []
    private(set) var chords: [ChordDefinition] = []
    private(set) var userShapes: [Shape] = []
    private(set) var entries: [LibraryEntry] = []

    var query: String = "" {
        didSet { refresh() }
    }
    var kindFilter: LibraryEntryKind? {
        didSet { refresh() }
    }
    var familyFilter: String? {
        didSet { refresh() }
    }
    var favouritesOnly = false {
        didSet { refresh() }
    }
    var tagFilter: String? {
        didSet { refresh() }
    }
    var sourceFilter: LibrarySource? {
        didSet { refresh() }
    }
    var sortOrder: LibrarySortOrder = .library {
        didSet { refresh() }
    }

    private(set) var results: [LibraryEntry] = []
    private(set) var favourites: Set<String> = []
    private(set) var tagsById: [String: [String]] = [:]

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let fuse = Fuse()
    @ObservationIgnored private var scalesById: [String: ScaleDefinition] = [:]
    @ObservationIgnored private var chordsById: [String: ChordDefinition] = [:]
    @ObservationIgnored private var sourcesById: [String: LibrarySource] = [:]
    @ObservationIgnored private let builtInIds: Set<String>

    /// Intervals listed in the library; selecting one shows the root and that interval.
    static let intervals: [(degree: Degree, name: String)] = [
        ("1", "Root"), ("b2", "Minor 2nd / 9th"), ("2", "Major 2nd / 9th"), ("b3", "Minor 3rd"),
        ("3", "Major 3rd"), ("4", "Perfect 4th / 11th"), ("#4", "Augmented 4th / 11th / Tritone"),
        ("5", "Perfect 5th"), ("b6", "Minor 6th / 13th"), ("6", "Major 6th / 13th"),
        ("b7", "Minor 7th"), ("7", "Major 7th"),
    ].map { (Degree($0.0)!, $0.1) }

    init(bundle: LibraryBundle, context: ModelContext) {
        self.builtIn = bundle
        self.context = context
        self.builtInIds = Set(bundle.scales.map(\.id) + bundle.chords.map(\.id))
        reload()
    }

    // MARK: - Loading

    /// Rebuilds everything from the built-in bundle and the saved user data.
    private func reload() {
        let decoder = JSONDecoder()
        let definitions = (try? context.fetch(FetchDescriptor<UserDefinition>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let shapes = (try? context.fetch(FetchDescriptor<UserShape>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []

        var sources: [String: LibrarySource] = [:]
        var userScales: [ScaleDefinition] = []
        var userChords: [ChordDefinition] = []

        for definition in definitions {
            let source: LibrarySource = definition.source.map { .imported($0) } ?? .mine
            if definition.kind == "scale", let scale = try? decoder.decode(ScaleDefinition.self, from: definition.data) {
                userScales.append(scale)
                sources[scale.id] = source
            } else if definition.kind == "chord", let chord = try? decoder.decode(ChordDefinition.self, from: definition.data) {
                userChords.append(chord)
                sources[chord.id] = source
            }
        }

        scales = builtIn.scales + userScales
        chords = builtIn.chords + userChords
        userShapes = shapes.compactMap { try? decoder.decode(Shape.self, from: $0.data) }
        scalesById = Dictionary(scales.map { ($0.id, $0) }, uniquingKeysWith: { _, user in user })
        chordsById = Dictionary(chords.map { ($0.id, $0) }, uniquingKeysWith: { _, user in user })
        sourcesById = sources

        let scaleEntries = scales.map { scale in
            LibraryEntry(id: scale.id, name: scale.name, kind: .scale,
                         detail: scale.family ?? "",
                         family: scale.family,
                         source: sources[scale.id] ?? .builtIn,
                         searchTerms: [scale.name] + scale.aliases)
        }
        let chordEntries = chords.map { chord in
            LibraryEntry(id: chord.id, name: chord.name, kind: .chord,
                         detail: chord.symbols.first(where: { !$0.isEmpty }) ?? "",
                         family: nil,
                         source: sources[chord.id] ?? .builtIn,
                         searchTerms: [chord.name] + chord.symbols.filter { !$0.isEmpty })
        }
        let intervalEntries = LibraryStore.intervals.map { interval in
            LibraryEntry(id: LibraryStore.intervalId(interval.degree), name: interval.name, kind: .interval,
                         detail: interval.degree.intervalName,
                         family: nil,
                         source: .builtIn,
                         searchTerms: [interval.name, interval.degree.intervalName])
        }
        entries = scaleEntries + chordEntries + intervalEntries

        let states = (try? context.fetch(FetchDescriptor<LibraryItemState>())) ?? []
        favourites = Set(states.filter(\.favourite).map(\.definitionId))
        tagsById = Dictionary(states.filter { !$0.tags.isEmpty }.map { ($0.definitionId, $0.tags) }, uniquingKeysWith: { first, _ in first })

        refresh()
    }

    // MARK: - Lookup

    /// Scale families in library order, for the sidebar.
    var scaleFamilies: [String] {
        var seen = Set<String>()
        return scales.compactMap(\.family).filter { seen.insert($0).inserted }
    }

    /// Every tag in use, alphabetically.
    var allTags: [String] {
        Set(tagsById.values.flatMap { $0 }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Sources present in the library: built-in, mine, then each imported bundle.
    var sources: [LibrarySource] {
        var seen = Set<LibrarySource>()
        return ([.builtIn, .mine] + entries.map(\.source)).filter { source in
            entries.contains { $0.source == source } && seen.insert(source).inserted
        }
    }

    /// Shows everything again.
    func clearFilters() {
        kindFilter = nil
        familyFilter = nil
        favouritesOnly = false
        tagFilter = nil
        sourceFilter = nil
    }

    static func intervalId(_ degree: Degree) -> String {
        "builtin.interval.\(degree)"
    }

    static func newUserId() -> String {
        "user.\(UUID().uuidString.lowercased())"
    }

    func scale(_ id: String) -> ScaleDefinition? {
        scalesById[id]
    }

    func chord(_ id: String) -> ChordDefinition? {
        chordsById[id]
    }

    func interval(_ id: String) -> Degree? {
        LibraryStore.intervals.first { LibraryStore.intervalId($0.degree) == id }?.degree
    }

    func entry(_ id: String) -> LibraryEntry? {
        entries.first { $0.id == id }
    }

    func isBuiltIn(_ id: String) -> Bool {
        builtInIds.contains(id)
    }

    /// Your shapes for a definition on a tuning.
    func userShapes(for definitionId: String, tuningId: String) -> [Shape] {
        userShapes.filter { $0.definitionId == definitionId && $0.tuningId == tuningId }
    }

    func isUserShape(_ id: String) -> Bool {
        userShapes.contains { $0.id == id }
    }

    // MARK: - Favourites and tags

    func isFavourite(_ id: String) -> Bool {
        favourites.contains(id)
    }

    func toggleFavourite(_ id: String) {
        let state = itemState(id)
        state.favourite.toggle()
        try? context.save()

        if state.favourite {
            favourites.insert(id)
        } else {
            favourites.remove(id)
        }

        if favouritesOnly {
            refresh()
        }
    }

    func tags(_ id: String) -> [String] {
        tagsById[id] ?? []
    }

    func setTags(_ tags: [String], for id: String) {
        var seen = Set<String>()
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }

        itemState(id).tags = cleaned
        try? context.save()
        tagsById[id] = cleaned.isEmpty ? nil : cleaned

        if tagFilter != nil {
            refresh()
        }
    }

    private func itemState(_ id: String) -> LibraryItemState {
        let descriptor = FetchDescriptor<LibraryItemState>(predicate: #Predicate { $0.definitionId == id })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let state = LibraryItemState(definitionId: id)
        context.insert(state)
        return state
    }

    // MARK: - Editing

    /// Problems saving this scale would cause, e.g. a malformed formula or a mode that doesn't match its parent.
    func issues(for scale: ScaleDefinition) -> [String] {
        let others = scales.filter { $0.id != scale.id }
        let bundle = LibraryBundle(bundle: .init(id: "check", name: "check"), scales: others + [scale], chords: [])
        return bundle.validate().filter { $0.contains(scale.id) }
    }

    /// Problems saving this chord would cause, e.g. a symbol another chord already uses.
    func issues(for chord: ChordDefinition) -> [String] {
        let others = chords.filter { $0.id != chord.id }
        let bundle = LibraryBundle(bundle: .init(id: "check", name: "check"), scales: [], chords: others + [chord])
        return bundle.validate().filter { $0.contains(chord.id) }
    }

    func save(_ scale: ScaleDefinition, source: String? = nil) {
        upsertDefinition(id: scale.id, kind: "scale", data: try? JSONEncoder().encode(scale), source: source)
        try? context.save()
        reload()
    }

    func save(_ chord: ChordDefinition, source: String? = nil) {
        upsertDefinition(id: chord.id, kind: "chord", data: try? JSONEncoder().encode(chord), source: source)
        try? context.save()
        reload()
    }

    /// Makes an editable copy of any scale or chord. Returns the copy's id.
    @discardableResult
    func duplicate(_ id: String) -> String? {
        let newId = LibraryStore.newUserId()
        if var scale = scale(id) {
            scale.id = newId
            scale.name += " (copy)"
            save(scale)
        } else if var chord = chord(id) {
            chord.id = newId
            chord.name += " (copy)"
            // Symbols must be unique, so the copy starts without them
            chord.symbols = []
            save(chord)
        } else {
            return nil
        }
        return newId
    }

    /// Deletes one of your definitions and its shapes. Built-in items can't be deleted.
    func deleteDefinition(_ id: String) {
        guard !isBuiltIn(id) else { return }
        try? context.delete(model: UserDefinition.self, where: #Predicate { $0.definitionId == id })
        try? context.delete(model: UserShape.self, where: #Predicate { $0.definitionId == id })
        try? context.save()
        reload()
    }

    func save(_ shape: Shape, source: String? = nil) {
        upsertShape(shape, source: source)
        try? context.save()
        reload()
    }

    func deleteShape(_ id: String) {
        try? context.delete(model: UserShape.self, where: #Predicate { $0.shapeId == id })
        try? context.save()
        reload()
    }

    private func upsertDefinition(id: String, kind: String, data: Data?, source: String?) {
        guard let data else { return }
        let descriptor = FetchDescriptor<UserDefinition>(predicate: #Predicate { $0.definitionId == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.data = data
            existing.kind = kind
            existing.source = source ?? existing.source
        } else {
            context.insert(UserDefinition(definitionId: id, kind: kind, data: data, source: source))
        }
    }

    private func upsertShape(_ shape: Shape, source: String?) {
        guard let data = try? JSONEncoder().encode(shape) else { return }
        let id = shape.id
        let descriptor = FetchDescriptor<UserShape>(predicate: #Predicate { $0.shapeId == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.data = data
            existing.definitionId = shape.definitionId
        } else {
            context.insert(UserShape(shapeId: shape.id, definitionId: shape.definitionId, data: data, source: source))
        }
    }

    // MARK: - Import and export

    func importPlan(for bundle: LibraryBundle) -> LibraryImport {
        let existing = Set(scales.map(\.id) + chords.map(\.id) + userShapes.map(\.id))
        return LibraryImport(bundle, existingIds: existing, builtInIds: builtInIds)
    }

    /// Adds an already-resolved bundle (see `LibraryImport.resolved`) to the library.
    func apply(_ bundle: LibraryBundle) {
        let source = bundle.bundle.name
        let encoder = JSONEncoder()
        for scale in bundle.scales where !isBuiltIn(scale.id) {
            upsertDefinition(id: scale.id, kind: "scale", data: try? encoder.encode(scale), source: source)
        }
        for chord in bundle.chords where !isBuiltIn(chord.id) {
            upsertDefinition(id: chord.id, kind: "chord", data: try? encoder.encode(chord), source: source)
        }
        for shape in bundle.shapes {
            upsertShape(shape, source: source)
        }
        try? context.save()
        reload()
    }

    func exportBundle(_ scope: LibraryExportScope, name: String) -> LibraryBundle {
        let info = LibraryBundle.Info(id: "user.\(UUID().uuidString.lowercased())", name: name)
        let include: (String) -> Bool
        switch scope {
        case .mine: include = { !self.isBuiltIn($0) }
        case .tag(let tag): include = { self.tags($0).contains(tag) }
        case .everything: include = { _ in true }
        }

        let scales = self.scales.filter { include($0.id) }
        let chords = self.chords.filter { include($0.id) }
        let definitionIds = Set(scales.map(\.id) + chords.map(\.id))
        // Your shapes go with their definitions, or all of them when exporting your own items
        let shapes = userShapes.filter { definitionIds.contains($0.definitionId) || scope == .mine || scope == .everything }

        return LibraryBundle(bundle: info, scales: scales, chords: chords, shapes: shapes)
    }

    // MARK: - Filtering

    private func refresh() {
        var filtered = entries.filter { entry in
            (kindFilter == nil || entry.kind == kindFilter)
                && (familyFilter == nil || entry.family == familyFilter)
                && (!favouritesOnly || favourites.contains(entry.id))
                && (tagFilter == nil || tags(entry.id).contains(tagFilter!))
                && (sourceFilter == nil || entry.source == sourceFilter)
        }

        if sortOrder == .name {
            filtered.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        // Search results are ordered by match quality instead
        if !query.isEmpty {
            filtered = fuse.searchSync(query, in: filtered, by: \LibraryEntry.properties).map { filtered[$0.index] }
        }

        results = filtered
    }
}
