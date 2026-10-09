//
//  IntervalName.swift
//  SpotCore
//

import Foundation

extension Degree {
    /// Interval name for fretboard labels: `R`, `m3`, `P5`, `A4`, `d5`, `d7`, `M9`, `A11`.
    /// Spelled from the degree, so `#4` and `b5` stay distinct.
    public var intervalName: String {
        if number == 1 && accidental == 0 {
            return "R"
        }

        let simple = (number - 1) % 7 + 1
        let isPerfect = [1, 4, 5].contains(simple)
        let quality: String

        switch (isPerfect, accidental) {
        case (true, 0): quality = "P"
        case (false, 0): quality = "M"
        case (false, -1): quality = "m"
        case (_, let a) where a > 0: quality = String(repeating: "A", count: a)
        case (true, let a): quality = String(repeating: "d", count: -a)
        case (false, let a): quality = String(repeating: "d", count: -a - 1)
        }

        return quality + String(number)
    }

    /// Default name for a note outside the current scale/chord, by semitones above the root.
    public static func chromaticIntervalName(_ semitones: Int) -> String {
        ["R", "m2", "M2", "m3", "M3", "P4", "TT", "P5", "m6", "M6", "m7", "M7"][PitchClass(semitones).value]
    }
}
