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
    /// The scale a chord was picked from in the chords-on-each-degree view, so it can stay on screen.
    struct ScaleContext {
        var root: PitchClass
        var scale: ScaleDefinition
        
        var spelledRoot: SpelledNote {
            SelectionState.key(root: root, formula: scale.formula).tonic
        }
    }
    
    var root: PitchClass = PitchClass(9) { // A
        didSet { scaleContext = nil }
    }
    private(set) var scaleContext: ScaleContext?
    var kind: LibraryEntryKind = .scale
    var scale: ScaleDefinition
    var chord: ChordDefinition
    var interval: Degree = Degree(5)
    var fretboard = Fretboard()
    /// Index into `shapes`; wraps, so it survives switching to a scale with fewer positions.
    var shapeIndex: Int = 0
    /// Show only one kind of shape ("CAGED", "Drop 2"...), remembered separately for scales and chords.
    var shapeSystemFilter: [LibraryEntryKind: String] = [:]
    
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
        SelectionState.key(root: root, formula: formula)
    }
    
    static func key(root: PitchClass, formula: Formula) -> Key {
        let offsets = formula.pitchClassOffsets
        let quality: KeyQuality = offsets.contains(3) && !offsets.contains(4) ? .minor : .major
        return Key(conventional: root, quality)
    }
    
    /// The scale whose chords to show: the selected scale, or the one the current chord was picked from.
    var chordSourceScale: ScaleContext? {
        kind == .scale ? ScaleContext(root: root, scale: scale) : scaleContext
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
        scaleContext = nil
    }

    /// Selects one of the chords built on the current scale, rooted on its scale degree.
    func select(_ diatonic: DiatonicChord) {
        guard let chord = diatonic.chord, let context = chordSourceScale else { return }
        root = context.root.transposed(by: diatonic.scaleDegree.pitchClassOffset)
        self.chord = chord
        kind = .chord
        scaleContext = context
    }
    
    func isSelected(_ diatonic: DiatonicChord) -> Bool {
        guard kind == .chord, let context = scaleContext else { return false }
        return diatonic.chord?.id == chord.id && context.root.transposed(by: diatonic.scaleDegree.pitchClassOffset) == root
    }
    
    /// Goes back to the scale a chord was picked from.
    func returnToScale() {
        guard let context = scaleContext else { return }
        root = context.root
        scale = context.scale
        kind = .scale
    }
    
    func transposeRoot(by semitones: Int) {
        root = root.transposed(by: semitones)
    }
    
    /// Positions for the selected scale, or voicings and arpeggios for the selected chord,
    /// narrowed to the chosen shape system if it applies.
    var shapes: [Shape] {
        let all = allShapes
        guard let system = shapeSystemFilter[kind], all.contains(where: { $0.system == system }) else {
            return all
        }
        return all.filter { $0.system == system }
    }
    
    /// The shape systems available for the current selection, in the order they first appear.
    var shapeSystems: [String] {
        var seen = Set<String>()
        return allShapes.map(\.system).filter { seen.insert($0).inserted }
    }
    
    var shapeSystem: String? {
        get { shapeSystems.contains(shapeSystemFilter[kind] ?? "") ? shapeSystemFilter[kind] : nil }
        set {
            shapeSystemFilter[kind] = newValue
            shapeIndex = 0
        }
    }
    
    private var allShapes: [Shape] {
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
            : ShapeGenerator.chordShapes(chord, root: root, fretboard: fretboard)
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
