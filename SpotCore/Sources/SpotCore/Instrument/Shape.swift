//
//  Shape.swift
//  SpotCore
//

import Foundation

/// One note of a shape. Frets are relative to the root's fret on the lowest string,
/// so the same shape works for every root.
public struct ShapeNote: Hashable, Codable, Sendable {
    public var string: Int
    public var fret: Int
    public var degree: Degree
    /// 1–4 for index to little finger, 0 for an open string.
    /// Nil means "work it out from where the shape is placed", which is what generated shapes use.
    public var finger: Int?

    public init(string: Int, fret: Int, degree: Degree, finger: Int? = nil) {
        self.string = string
        self.fret = fret
        self.degree = degree
        self.finger = finger
    }
}

public enum ShapeKind: String, Codable, Sendable {
    /// Notes played one after another; fingered string by string.
    case scale
    /// Notes played together; fingered as a chord grip.
    case chord
}

/// A concrete layout of a scale, arpeggio or chord voicing on a fretted instrument,
/// e.g. "3 notes per string, position 2" or "Drop 2, 1st inversion, strings 4–1".
public struct Shape: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var definitionId: String
    public var kind: ShapeKind
    /// The family of shapes this belongs to: "3 notes per string", "Drop 2", "Open", ...
    public var system: String
    public var name: String
    public var tuningId: String
    public var notes: [ShapeNote]

    public init(id: String, definitionId: String, kind: ShapeKind, system: String, name: String, tuningId: String, notes: [ShapeNote]) {
        self.id = id
        self.definitionId = definitionId
        self.kind = kind
        self.system = system
        self.name = name
        self.tuningId = tuningId
        self.notes = notes
    }

    /// The root's fret on the lowest string, 0...11. Shape frets are relative to this.
    public static func rootFret(_ root: PitchClass, on fretboard: Fretboard) -> Int {
        root.semitones(above: PitchClass(fretboard.tuning.strings[0]))
    }

    /// Every octave at which the whole shape fits on the fretboard, as fret positions.
    /// Notes without a stored finger get one suggested for that placement.
    public func placements(root: PitchClass, on fretboard: Fretboard) -> [[FretPosition: ShapeNote]] {
        guard !notes.isEmpty else {
            return []
        }

        let base = Shape.rootFret(root, on: fretboard)
        let frets = notes.map(\.fret)

        return (-2...2).compactMap { octave in
            let offset = base + octave * 12
            guard frets.min()! + offset >= 0, frets.max()! + offset <= fretboard.fretCount else {
                return nil
            }
            var placed = notes.map { note -> ShapeNote in
                var note = note
                note.fret += offset
                return note
            }
            if placed.contains(where: { $0.finger == nil }) {
                placed = Fingering.suggest(placed, kind: kind, stringCount: fretboard.stringCount)
            }
            return Dictionary(placed.map { (FretPosition(string: $0.string, fret: $0.fret), $0) },
                              uniquingKeysWith: { first, _ in first })
        }
    }

    /// All placements merged into one lookup, for highlighting.
    public func positions(root: PitchClass, on fretboard: Fretboard) -> [FretPosition: ShapeNote] {
        placements(root: root, on: fretboard).reduce(into: [:]) { result, placement in
            result.merge(placement) { first, _ in first }
        }
    }
}

/// Suggested fingers for notes placed on actual frets.
enum Fingering {
    /// Fills in missing fingers, keeping any that were set by hand.
    static func suggest(_ notes: [ShapeNote], kind: ShapeKind, stringCount: Int) -> [ShapeNote] {
        let suggested: [Int: Int]
        switch kind {
        case .scale:
            return Dictionary(grouping: notes, by: \.string)
                .sorted { $0.key < $1.key }
                .flatMap { _, stringNotes in
                    let sorted = stringNotes.sorted { $0.fret < $1.fret }
                    let fingers = scaleFingers(sorted.map(\.fret))
                    return zip(sorted, fingers).map { note, finger in
                        var note = note
                        note.finger = note.finger ?? finger
                        return note
                    }
                }
        case .chord:
            var frets = [Int?](repeating: nil, count: stringCount)
            for note in notes { frets[note.string] = note.fret }
            suggested = chordFingers(frets) ?? [:]
        }
        return notes.map { note in
            var note = note
            note.finger = note.finger ?? suggested[note.string]
            return note
        }
    }

    /// Fingers for the notes on one string, in fret order: index on the first fretted note,
    /// one finger per fret, and 1-2-4 / 1-4 when the notes stretch wider than four frets.
    static func scaleFingers(_ frets: [Int]) -> [Int] {
        let fretted = frets.filter { $0 > 0 }
        guard let first = fretted.first, let last = fretted.last else {
            return frets.map { _ in 0 }
        }
        let isStretch = last - first > 3
        var frettedIndex = 0

        return frets.map { fret in
            defer { if fret > 0 { frettedIndex += 1 } }
            if fret <= 0 {
                return 0
            }
            if isStretch {
                return frettedIndex == 0 ? 1 : (fret == last ? 4 : 2)
            }
            return 1 + fret - first
        }
    }

    /// Index finger on the lowest fret (as a barre if several strings share it), then one finger
    /// per fret, moving to the next finger when two notes share a fret. Nil if it needs a fifth finger.
    /// `frets` is indexed by string, nil for muted strings.
    static func chordFingers(_ frets: [Int?]) -> [Int: Int]? {
        var fingers: [Int: Int] = [:]
        let fretted = frets.indices.filter { (frets[$0] ?? 0) > 0 }

        for string in frets.indices where frets[string] == 0 {
            fingers[string] = 0
        }

        guard let minFret = fretted.map({ frets[$0]! }).min() else {
            return fingers
        }

        for string in fretted where frets[string] == minFret {
            fingers[string] = 1
        }

        var previous = 1
        let rest = fretted
            .filter { frets[$0]! > minFret }
            .sorted { (frets[$0]!, $0) < (frets[$1]!, $1) }

        for string in rest {
            let finger = max(1 + frets[string]! - minFret, previous + 1)
            guard finger <= 4 else {
                return nil
            }
            fingers[string] = finger
            previous = finger
        }

        return fingers
    }
}
