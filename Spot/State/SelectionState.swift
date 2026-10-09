//
//  SelectionState.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

/// What is shown on the instrument: root, the selected scale/chord/interval and its position.
@Observable
final class SelectionState {
    var root: PitchClass = PitchClass(9) // A
    var kind: LibraryEntryKind = .scale
    var scale: ScaleDefinition
    var chord: ChordDefinition
    var interval: Degree = Degree(5)
    /// Index of the selected scale position (3-notes-per-string shape for now).
    var position: Int = 0

    init(scale: ScaleDefinition, chord: ChordDefinition) {
        self.scale = scale
        self.chord = chord
    }

    var formula: Formula {
        switch kind {
        case .scale: return scale.formula
        case .chord: return chord.formula
        case .interval: return Formula(interval == Degree(1) ? [Degree(1)] : [Degree(1), interval])
        }
    }

    var selectedId: String {
        switch kind {
        case .scale: return scale.id
        case .chord: return chord.id
        case .interval: return LibraryStore.intervalId(interval)
        }
    }

    /// The key used to spell notes: minor-sounding collections spell from a minor key (C♯ minor, not D♭ minor).
    var key: Key {
        let offsets = formula.pitchClassOffsets
        let quality: KeyQuality = offsets.contains(3) && !offsets.contains(4) ? .minor : .major
        return Key(conventional: root, quality)
    }

    var spelledRoot: SpelledNote {
        key.tonic
    }

    var title: String {
        switch kind {
        case .scale: return "\(spelledRoot) \(scale.name)"
        case .chord: return "\(spelledRoot)\(chord.displaySymbol)  \(chord.name)"
        case .interval: return "\(spelledRoot) + \(interval.intervalName)"
        }
    }

    func select(_ entry: LibraryEntry, in library: LibraryStore) {
        switch entry.kind {
        case .scale:
            guard let scale = library.scale(entry.id) else { return }
            self.scale = scale
        case .chord:
            guard let chord = library.chord(entry.id) else { return }
            self.chord = chord
        case .interval:
            guard let interval = library.interval(entry.id) else { return }
            self.interval = interval
        }
        kind = entry.kind
    }

    func transposeRoot(by semitones: Int) {
        root = root.transposed(by: semitones)
    }
}
