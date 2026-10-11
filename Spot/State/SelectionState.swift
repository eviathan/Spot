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
    
    /// A shape being drawn on the fretboard (see `startNewShape`).
    struct ShapeDraft {
        var editingId: String?
        var name: String
        var system: String
        var kind: ShapeKind
        /// Positions in the shape, with a finger if one was set by hand (nil means suggest one).
        var notes: [FretPosition: Int?]
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
    
    var shapeDraft: ShapeDraft?
    
    let library: LibraryStore
    
    // Generated shapes, keyed by what they depend on. Chord voicings depend on the root.
    @ObservationIgnored private var shapeCache: [String: [Shape]] = [:]

    init(scale: ScaleDefinition, chord: ChordDefinition, library: LibraryStore) {
        self.scale = scale
        self.chord = chord
        self.library = library
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

    /// The key used to spell notes: minor-sounding collections spell from a minor key (C♯ minor, not D♭ minor), and
    /// a scale that's a key's notes (a mode) from that key.
    var key: Key {
        if kind == .scale, let quality = KeyQuality(scaleId: scale.id) {
            return Key(conventional: root, quality)
        }
        return SelectionState.key(root: root, formula: formula)
    }

    /// The key the Library is in: when the selected scale is a key's notes (major, minor or a mode).
    var keyQuality: KeyQuality? {
        kind == .scale ? KeyQuality(scaleId: scale.id) : nil
    }

    /// Shows a scale (picked from the key control), as if picked in the list.
    func selectScale(_ scale: ScaleDefinition) {
        self.scale = scale
        kind = .scale
        scaleContext = nil
        shapeDraft = nil
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

    /// Re-reads the selected definitions after they were edited, or falls back if one was deleted.
    func refreshDefinitions() {
        if let updated = library.scale(scale.id) { scale = updated } else { scale = library.scales[0] }
        if let updated = library.chord(chord.id) { chord = updated } else { chord = library.chords[0] }
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
        shapeDraft = nil
    }

    /// Selects one of the chords built on the current scale, rooted on its scale degree.
    func select(_ diatonic: DiatonicChord) {
        guard let chord = diatonic.chord, let context = chordSourceScale else { return }
        root = context.root.transposed(by: diatonic.scaleDegree.pitchClassOffset)
        self.chord = chord
        kind = .chord
        scaleContext = context
        shapeDraft = nil
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
    
    /// Your shapes first, then generated ones.
    private var allShapes: [Shape] {
        guard kind != .interval else { return [] }
        return library.userShapes(for: selectedId, tuningId: fretboard.tuning.id) + generatedShapes
    }
    
    private var generatedShapes: [Shape] {
        // The formula is part of the key so editing a definition regenerates its shapes
        let key: String
        switch kind {
        case .scale: key = "\(fretboard.tuning.id):\(scale.id):\(scale.formula)"
        case .chord: key = "\(fretboard.tuning.id):\(chord.id):\(chord.formula):\(chord.optional.sorted()):\(root.value)"
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
    
    // MARK: - Drawing shapes
    
    /// Starts drawing a shape on the fretboard, empty or as a copy of the current shape.
    func startNewShape(copyingCurrent: Bool) {
        var notes: [FretPosition: Int?] = [:]
        if copyingCurrent, let placement = currentShape?.placements(root: root, on: fretboard).first {
            for (position, note) in placement {
                notes[position] = .some(nil)
                // Keep fingers that were set by hand on the original
                if currentShape.map({ library.isUserShape($0.id) }) == true {
                    notes[position] = .some(note.finger)
                }
            }
        }
        let name = copyingCurrent ? (currentShape?.name ?? "My shape") : "My shape"
        shapeDraft = ShapeDraft(editingId: nil, name: name, system: "Mine",
                                kind: kind == .chord ? .chord : .scale, notes: notes)
    }
    
    /// Edits the current shape, if it's one of yours.
    func editCurrentShape() {
        guard let shape = currentShape, library.isUserShape(shape.id),
              let placement = shape.placements(root: root, on: fretboard).first else { return }
        var notes: [FretPosition: Int?] = [:]
        let base = placement.keys.map(\.fret).min()! - shape.notes.map(\.fret).min()!
        for note in shape.notes {
            notes[FretPosition(string: note.string, fret: note.fret + base)] = .some(note.finger)
        }
        shapeDraft = ShapeDraft(editingId: shape.id, name: shape.name, system: shape.system, kind: shape.kind, notes: notes)
    }
    
    func cancelShapeDraft() {
        shapeDraft = nil
    }
    
    /// Adds or removes a note. Only notes of the selected scale or chord can be added.
    func toggleDraftNote(at position: FretPosition) {
        guard shapeDraft != nil else { return }
        if shapeDraft!.notes[position] != nil {
            shapeDraft!.notes[position] = nil
        } else if degree(at: position) != nil {
            shapeDraft!.notes[position] = .some(nil)
        }
    }
    
    /// Sets the finger for a note in the draft; nil goes back to a suggested finger.
    func setDraftFinger(_ finger: Int?, at position: FretPosition) {
        guard shapeDraft?.notes[position] != nil else { return }
        shapeDraft!.notes[position] = .some(finger)
    }
    
    /// The draft as a shape, with frets relative to the root like any other shape.
    var draftShape: Shape? {
        guard let draft = shapeDraft, !draft.notes.isEmpty else { return nil }
        let rootFret = Shape.rootFret(root, on: fretboard)
        let notes = draft.notes.compactMap { position, finger -> ShapeNote? in
            guard let degree = degree(at: position) else { return nil }
            return ShapeNote(string: position.string, fret: position.fret - rootFret, degree: degree, finger: finger)
        }
        .sorted { ($0.string, $0.fret) < ($1.string, $1.fret) }
        
        return Shape(id: draft.editingId ?? LibraryStore.newUserId(),
                     definitionId: selectedId,
                     kind: draft.kind,
                     system: draft.system.trimmingCharacters(in: .whitespaces).isEmpty ? "Mine" : draft.system,
                     name: draft.name,
                     tuningId: fretboard.tuning.id,
                     notes: notes)
    }
    
    /// The draft's notes where they sit on the fretboard, with suggested fingers filled in.
    var draftPositions: [FretPosition: ShapeNote]? {
        guard let draft = shapeDraft else { return nil }
        guard let shape = draftShape else { return [:] }
        let wanted = Set(draft.notes.keys)
        return shape.placements(root: root, on: fretboard).first { Set($0.keys) == wanted } ?? [:]
    }
    
    /// Saves the draft and shows it.
    func saveShapeDraft() {
        guard let shape = draftShape else { return }
        library.save(shape)
        shapeDraft = nil
        shapeSystemFilter[kind] = nil
        shapeIndex = shapes.firstIndex { $0.id == shape.id } ?? 0
    }
    
    func deleteCurrentShape() {
        guard let shape = currentShape, library.isUserShape(shape.id) else { return }
        library.deleteShape(shape.id)
    }
    
    private func degree(at position: FretPosition) -> Degree? {
        let offset = fretboard.pitchClass(at: position).semitones(above: root)
        return formula.degrees.first { $0.pitchClassOffset == offset }
    }
}
