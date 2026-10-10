//
//  FretMarker.swift
//  SpotCore
//

import Foundation

/// Everything the fretboard view needs to draw one note. Built once per selection change.
public struct FretMarker: Identifiable, Hashable, Sendable {
    public var position: FretPosition
    public var pitchClass: PitchClass
    /// Semitones above the root, 0...11. Used for interval colours.
    public var semitonesAboveRoot: Int
    /// The scale/chord degree this note plays, or nil when it is outside the collection.
    public var degree: Degree?
    /// Whether the note is inside the selected position/shape. True everywhere when no shape applies.
    public var isInPosition: Bool
    /// Suggested finger from the selected shape: 1–4, 0 for open, nil if not in the shape.
    public var finger: Int?
    public var noteName: SpelledNote
    public var intervalName: String

    public init(position: FretPosition, pitchClass: PitchClass, semitonesAboveRoot: Int, degree: Degree?,
                isInPosition: Bool, finger: Int?, noteName: SpelledNote, intervalName: String) {
        self.position = position
        self.pitchClass = pitchClass
        self.semitonesAboveRoot = semitonesAboveRoot
        self.degree = degree
        self.isInPosition = isInPosition
        self.finger = finger
        self.noteName = noteName
        self.intervalName = intervalName
    }

    public var id: FretPosition {
        position
    }

    public var isInCollection: Bool {
        degree != nil
    }

    public var isOpenString: Bool {
        position.fret == 0
    }

    /// Builds a marker for every position on the fretboard.
    /// - Parameters:
    ///   - key: spells notes outside the formula.
    ///   - shape: the selected shape's notes by position, or nil if no shape applies.
    public static func build(fretboard: Fretboard, root: SpelledNote, formula: Formula,
                             key: Key, shape: [FretPosition: ShapeNote]?) -> [FretMarker] {
        let rootPitchClass = root.pitchClass

        // First degree wins if two degrees share a pitch class
        var degreesByOffset: [Int: Degree] = [:]
        for degree in formula.degrees where degreesByOffset[degree.pitchClassOffset] == nil {
            degreesByOffset[degree.pitchClassOffset] = degree
        }

        return fretboard.allPositions.map { position in
            let pitchClass = fretboard.pitchClass(at: position)
            let offset = pitchClass.semitones(above: rootPitchClass)
            let degree = degreesByOffset[offset]

            return FretMarker(
                position: position,
                pitchClass: pitchClass,
                semitonesAboveRoot: offset,
                degree: degree,
                isInPosition: shape.map { $0[position] != nil } ?? true,
                finger: shape?[position]?.finger,
                noteName: degree.map(root.spelling) ?? key.spell(pitchClass),
                intervalName: degree?.intervalName ?? Degree.chromaticIntervalName(offset)
            )
        }
    }
}
