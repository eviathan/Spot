//
//  Degree.swift
//  SpotCore
//

import Foundation

/// A spelled scale/chord degree relative to a root, e.g. `1`, `b3`, `#11`, `bb7`.
///
/// Unlike a raw semitone count, a degree keeps its letter distance, so `#4` and `b5`
/// sound the same but spell differently (F♯ vs G♭ over C).
public struct Degree: Hashable, Comparable, Sendable, CustomStringConvertible, LosslessStringConvertible {
    /// 1-based degree number. 8 and above are compound (9 = 2nd an octave up).
    public let number: Int
    /// Sharps are positive, flats negative.
    public let accidental: Int

    private static let majorScaleSemitones = [0, 2, 4, 5, 7, 9, 11]

    public init(_ number: Int, accidental: Int = 0) {
        precondition(number >= 1, "Degree numbers start at 1")
        self.number = number
        self.accidental = accidental
    }

    /// Parses `"b3"`, `"#11"`, `"bb7"`, `"♭9"`, `"5"`.
    public init?(_ description: String) {
        var accidental = 0
        var digits = Substring(description.trimmingCharacters(in: .whitespaces))

        while let first = digits.first, !first.isNumber {
            switch first {
            case "b", "♭": accidental -= 1
            case "#", "♯": accidental += 1
            default: return nil
            }
            digits = digits.dropFirst()
        }

        guard let number = Int(digits), number >= 1 else {
            return nil
        }

        self.init(number, accidental: accidental)
    }

    /// Semitones above the root, keeping compound degrees above the octave (9 = 14).
    public var semitones: Int {
        let index = (number - 1) % 7
        let octaves = (number - 1) / 7
        return Degree.majorScaleSemitones[index] + octaves * 12 + accidental
    }

    /// Semitones above the root folded into one octave, 0...11.
    public var pitchClassOffset: Int {
        PitchClass(semitones).value
    }

    /// Letter steps above the root's letter, 0...6.
    public var letterSteps: Int {
        (number - 1) % 7
    }

    public var description: String {
        String(repeating: accidental < 0 ? "b" : "#", count: abs(accidental)) + String(number)
    }

    /// Display form using ♭/♯ glyphs.
    public var prettyDescription: String {
        String(repeating: accidental < 0 ? "♭" : "♯", count: abs(accidental)) + String(number)
    }

    public static func < (lhs: Degree, rhs: Degree) -> Bool {
        (lhs.semitones, lhs.number) < (rhs.semitones, rhs.number)
    }
}

extension Degree: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let degree = Degree(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid degree \"\(string)\"")
        }
        self = degree
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
