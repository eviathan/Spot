//
//  ThreeNotePerString.swift
//  SpotCore
//

import Foundation

// TODO: Replace with the generated shape systems (Plan.md, Library v2)
/// The hand-entered 3-notes-per-string positions of the major scale, ported from the app.
/// Only defined for 6-string standard tuning.
public enum ThreeNotePerString {
    /// One shape per major mode (Ionian ... Locrian) for E major,
    /// each listed from the high E string down to the low E string.
    static let shapes: [[[Int]]] = [
        [[2, 4, 5], [2, 4, 5], [1, 2, 4], [1, 2, 4], [0, 2, 4], [0, 2, 4]],
        [[4, 5, 7], [4, 5, 7], [2, 4, 6], [2, 4, 6], [2, 4, 6], [2, 4, 5]],
        [[5, 7, 9], [5, 7, 9], [4, 6, 8], [4, 6, 7], [4, 6, 7], [4, 5, 7]],
        [[7, 9, 11], [7, 9, 10], [6, 8, 9], [6, 7, 9], [6, 7, 9], [5, 7, 9]],
        [[9, 11, 12], [9, 10, 12], [8, 9, 11], [7, 9, 11], [7, 9, 11], [7, 9, 11]],
        [[11, 12, 14], [10, 12, 14], [9, 11, 13], [9, 11, 13], [9, 11, 12], [9, 11, 12]],
        [[12, 14, 16], [12, 14, 16], [11, 13, 14], [11, 13, 14], [11, 12, 14], [11, 12, 14]],
    ]

    private static let majorScaleSemitones = [0, 2, 4, 5, 7, 9, 11]

    public static var positionCount: Int {
        shapes.count
    }

    /// Which major-scale mode a scale is, if any: 1 for Major, 2 for Dorian ... 7 for Locrian.
    public static func majorModeDegree(of scale: ScaleDefinition) -> Int? {
        if scale.id == "builtin.scale.major" {
            return 1
        }
        if let parent = scale.parent, parent.id == "builtin.scale.major" {
            return parent.degree
        }
        return nil
    }

    /// Fret positions in the given position of a major mode, repeated every octave up the neck.
    /// Returns nil when there is no pattern for this scale or tuning.
    public static func positions(scale: ScaleDefinition, root: PitchClass, position: Int, fretboard: Fretboard) -> Set<FretPosition>? {
        guard fretboard.tuning.strings == Tuning.standard.strings,
              let degree = majorModeDegree(of: scale) else {
            return nil
        }

        let shape = shapes[(position + degree - 1) % shapes.count]
        // Shapes are drawn for the parent major scale (G major for A Dorian), so shift from its root
        let parentRoot = root.transposed(by: -majorScaleSemitones[degree - 1])
        let offset = parentRoot.semitones(above: PitchClass(fretboard.tuning.strings[0]))
        var result = Set<FretPosition>()

        for (row, frets) in shape.enumerated() {
            let string = fretboard.stringCount - 1 - row
            for fret in frets {
                var octaveFret = (fret + offset) % 12
                while octaveFret <= fretboard.fretCount {
                    result.insert(FretPosition(string: string, fret: octaveFret))
                    octaveFret += 12
                }
            }
        }

        return result
    }
}
