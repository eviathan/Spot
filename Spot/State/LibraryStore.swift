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

/// A row in the library list.
struct LibraryEntry: Identifiable, Hashable, Searchable {
    let id: String
    let name: String
    let kind: LibraryEntryKind
    let detail: String
    let searchTerms: [String]

    var properties: [FuseProp] {
        searchTerms.map { FuseProp($0) }
    }
}

@Observable
final class LibraryStore {
    let bundle: LibraryBundle
    let entries: [LibraryEntry]

    var query: String = "" {
        didSet { results = search(query) }
    }

    private(set) var results: [LibraryEntry]
    private(set) var favourites: Set<String>

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let fuse = Fuse()
    @ObservationIgnored private let scalesById: [String: ScaleDefinition]
    @ObservationIgnored private let chordsById: [String: ChordDefinition]

    /// Intervals listed in the library; selecting one shows the root and that interval.
    static let intervals: [(degree: Degree, name: String)] = [
        ("1", "Root"), ("b2", "Minor 2nd / 9th"), ("2", "Major 2nd / 9th"), ("b3", "Minor 3rd"),
        ("3", "Major 3rd"), ("4", "Perfect 4th / 11th"), ("#4", "Augmented 4th / 11th / Tritone"),
        ("5", "Perfect 5th"), ("b6", "Minor 6th / 13th"), ("6", "Major 6th / 13th"),
        ("b7", "Minor 7th"), ("7", "Major 7th"),
    ].map { (Degree($0.0)!, $0.1) }

    init(bundle: LibraryBundle, context: ModelContext) {
        self.bundle = bundle
        self.context = context

        scalesById = Dictionary(uniqueKeysWithValues: bundle.scales.map { ($0.id, $0) })
        chordsById = Dictionary(uniqueKeysWithValues: bundle.chords.map { ($0.id, $0) })

        let scaleEntries = bundle.scales.map { scale in
            LibraryEntry(id: scale.id, name: scale.name, kind: .scale,
                         detail: scale.family ?? "",
                         searchTerms: [scale.name] + scale.aliases)
        }
        let chordEntries = bundle.chords.map { chord in
            LibraryEntry(id: chord.id, name: chord.name, kind: .chord,
                         detail: chord.symbols.first(where: { !$0.isEmpty }) ?? "",
                         searchTerms: [chord.name] + chord.symbols.filter { !$0.isEmpty })
        }
        let intervalEntries = LibraryStore.intervals.map { interval in
            LibraryEntry(id: LibraryStore.intervalId(interval.degree), name: interval.name, kind: .interval,
                         detail: interval.degree.intervalName,
                         searchTerms: [interval.name, interval.degree.intervalName])
        }

        entries = scaleEntries + chordEntries + intervalEntries
        results = entries

        let states = (try? context.fetch(FetchDescriptor<LibraryItemState>())) ?? []
        favourites = Set(states.filter(\.favourite).map(\.definitionId))
    }

    static func intervalId(_ degree: Degree) -> String {
        "builtin.interval.\(degree)"
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

    private func search(_ query: String) -> [LibraryEntry] {
        guard !query.isEmpty else {
            return entries
        }

        let results = fuse.searchSync(query, in: entries, by: \LibraryEntry.properties)
        return results.map { entries[$0.index] }
    }
}
