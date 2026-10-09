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
    public var noteName: SpelledNote
    public var intervalName: String

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
    ///   - positionFilter: positions in the selected shape, or nil if no shape applies.
    public static func build(fretboard: Fretboard, root: SpelledNote, formula: Formula,
                             key: Key, positionFilter: Set<FretPosition>?) -> [FretMarker] {
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
                isInPosition: positionFilter?.contains(position) ?? true,
                noteName: degree.map(root.spelling) ?? key.spell(pitchClass),
                intervalName: degree?.intervalName ?? Degree.chromaticIntervalName(offset)
            )
        }
    }
}
