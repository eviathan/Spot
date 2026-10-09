//
//  SelectionState.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

/// What is shown on the instrument: root, the selected scale/chord/interval and its shape.
@Observable
final class SelectionState {
    var root: PitchClass = PitchClass(9) // A
    var kind: LibraryEntryKind = .scale
    var scale: ScaleDefinition
    var chord: ChordDefinition
    var interval: Degree = Degree(5)
    var fretboard = Fretboard()
    /// Index into `shapes`; wraps, so it survives switching to a scale with fewer positions.
    var shapeIndex: Int = 0
    
    // Generated shapes, keyed by what they depend on. Chord voicings depend on the root.
    @ObservationIgnored private var shapeCache: [String: [Shape]] = [:]

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
    
    /// Positions for the selected scale, or voicings for the selected chord.
    var shapes: [Shape] {
        let key: String
        switch kind {
        case .scale: key = "\(fretboard.tuning.id):\(scale.id)"
        case .chord: key = "\(fretboard.tuning.id):\(chord.id):\(root.value)"
        case .interval: return []
        }
        
        if let cached = shapeCache[key] {
            return cached
        }
        
        let shapes = kind == .scale
            ? ShapeGenerator.scalePositions(scale, fretboard: fretboard)
            : ShapeGenerator.chordVoicings(chord, root: root, fretboard: fretboard)
        shapeCache[key] = shapes
        return shapes
    }
    
    var currentShapeIndex: Int? {
        let count = shapes.count
        return count == 0 ? nil : ((shapeIndex % count) + count) % count
    }
    
    var currentShape: Shape? {
        currentShapeIndex.map { shapes[$0] }
    }
    
    func nextShape() {
        shapeIndex = (currentShapeIndex ?? -1) + 1
    }
    
    func previousShape() {
        shapeIndex = (currentShapeIndex ?? 1) - 1
    }
}
