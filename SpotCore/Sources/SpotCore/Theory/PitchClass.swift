//
//  PitchClass.swift
//  SpotCore
//

import Foundation

/// A pitch with octave and spelling removed: 0 = C, 1 = C♯/D♭ ... 11 = B.
public struct PitchClass: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) {
        self.value = ((value % 12) + 12) % 12
    }

    public func transposed(by semitones: Int) -> PitchClass {
        PitchClass(value + semitones)
    }

    /// Semitones from `other` up to this pitch class, in 0...11.
    public func semitones(above other: PitchClass) -> Int {
        PitchClass(value - other.value).value
    }

    public static func < (lhs: PitchClass, rhs: PitchClass) -> Bool {
        lhs.value < rhs.value
    }

    public var description: String {
        SpelledNote.conventional(self).description
    }
}
