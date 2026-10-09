//
//  DiatonicChords.swift
//  SpotCore
//

import Foundation

/// A chord built by stacking thirds on one degree of a scale, e.g. the ii7 of major.
public struct DiatonicChord: Hashable, Sendable {
    /// The chord's root as a degree of the scale, e.g. `b3` for the ♭III of minor.
    public var scaleDegree: Degree
    /// Roman numeral: `ii`, `♭III`, `vii°`, `V7`, `iiø7`, `IVmaj7`.
    public var numeral: String
    /// The chord's own formula from its root, e.g. `1 b3 5 b7`.
    public var formula: Formula
    /// The matching library chord, if there is one.
    public var chord: ChordDefinition?
    /// The chord tones as degrees of the scale, for colouring by the scale's intervals.
    public var scaleDegrees: [Degree]
}

public enum DiatonicChords {
    /// Triads (`size` 3) or seventh chords (`size` 4) on each degree of a 7-note scale.
    /// Returns nothing for other scales, where stacking thirds isn't well defined.
    public static func build(scale: Formula, size: Int, chords: [ChordDefinition]) -> [DiatonicChord] {
        var seen = Set<Int>()
        let degrees = scale.degrees
            .sorted { $0.pitchClassOffset < $1.pitchClassOffset }
            .filter { seen.insert($0.pitchClassOffset).inserted }

        guard degrees.count == 7, (3...4).contains(size) else {
            return []
        }

        return degrees.indices.map { index in
            let scaleDegrees = (0..<size).map { degrees[(index + $0 * 2) % 7] }
            let rootOffset = scaleDegrees[0].pitchClassOffset

            // Spell each tone as the 1st, 3rd, 5th or 7th above the chord root
            let formula = Formula(scaleDegrees.enumerated().map { stack, degree in
                let number = stack * 2 + 1
                let semitones = PitchClass(degree.pitchClassOffset - rootOffset).value
                return Degree(number, accidental: semitones - Degree(number).semitones)
            })

            let chord = chords.first { $0.formula == formula }
                ?? chords.first { $0.formula.pitchClassOffsets == formula.pitchClassOffsets && $0.formula.degrees.count == size }

            return DiatonicChord(scaleDegree: scaleDegrees[0],
                                 numeral: numeral(scaleDegree: scaleDegrees[0], formula: formula),
                                 formula: formula,
                                 chord: chord,
                                 scaleDegrees: scaleDegrees)
        }
    }

    static func numeral(scaleDegree: Degree, formula: Formula) -> String {
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let has = { (text: String) in formula.degrees.contains(Degree(text)!) }

        let isMinorThird = has("b3")
        let base = numerals[scaleDegree.letterSteps]
        let accidental = String(repeating: scaleDegree.accidental < 0 ? "♭" : "♯", count: abs(scaleDegree.accidental))
        let roman = isMinorThird ? base.lowercased() : base

        let suffix: String
        if formula.degrees.count == 3 {
            suffix = has("b5") && isMinorThird ? "°" : (has("#5") ? "+" : "")
        } else if has("b5") && has("bb7") {
            suffix = "°7"
        } else if has("b5") && has("b7") && isMinorThird {
            suffix = "ø7"
        } else if has("7") {
            suffix = has("#5") ? "+maj7" : (isMinorThird ? "(maj7)" : "maj7")
        } else {
            suffix = "7"
        }

        return accidental + roman + suffix
    }
}
