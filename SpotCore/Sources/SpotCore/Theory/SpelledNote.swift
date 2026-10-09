//
//  SpelledNote.swift
//  SpotCore
//

import Foundation

/// A pitch class with a specific spelling, e.g. F♯ rather than G♭.
public struct SpelledNote: Hashable, Sendable, CustomStringConvertible, LosslessStringConvertible {
    public let letter: Letter
    /// Sharps are positive, flats negative.
    public let accidental: Int

    public init(_ letter: Letter, accidental: Int = 0) {
        self.letter = letter
        self.accidental = accidental
    }

    /// Parses `"C"`, `"F#"`, `"Bb"`, `"E♭"`, `"Fx"`/`"F𝄪"` (double sharp), `"Bbb"`/`"B𝄫"`.
    public init?(_ description: String) {
        guard let (note, rest) = SpelledNote.parsePrefix(Substring(description)), rest.isEmpty else {
            return nil
        }
        self = note
    }

    public var pitchClass: PitchClass {
        letter.naturalPitchClass.transposed(by: accidental)
    }

    /// The note `degree` above this one, spelled with the correct letter
    /// (e.g. the 7th of G♯ major is F𝄪, not G).
    public func spelling(_ degree: Degree) -> SpelledNote {
        let letter = self.letter.advanced(by: degree.letterSteps)
        let target = pitchClass.transposed(by: degree.semitones)
        var accidental = target.semitones(above: letter.naturalPitchClass)
        if accidental > 6 {
            accidental -= 12
        }
        return SpelledNote(letter, accidental: accidental)
    }

    public var description: String {
        let accidentalText: String
        switch accidental {
        case 0: accidentalText = ""
        case 2: accidentalText = "𝄪"
        case -2: accidentalText = "𝄫"
        default:
            accidentalText = String(repeating: accidental < 0 ? "♭" : "♯", count: abs(accidental))
        }
        return letter.description + accidentalText
    }

    /// Plain-text spelling (`"Bb"`, `"F#"`, `"Fx"`) used in files and chord symbols.
    public var asciiDescription: String {
        if accidental == 2 {
            return letter.description + "x"
        }
        return letter.description + String(repeating: accidental < 0 ? "b" : "#", count: abs(accidental))
    }

    /// The everyday name for a pitch class out of key context: C, D♭, D, E♭, E, F, F♯, G, A♭, A, B♭, B.
    public static func conventional(_ pitchClass: PitchClass) -> SpelledNote {
        conventionalNames[pitchClass.value]
    }

    private static let conventionalNames: [SpelledNote] = [
        SpelledNote(.C), SpelledNote(.D, accidental: -1), SpelledNote(.D), SpelledNote(.E, accidental: -1),
        SpelledNote(.E), SpelledNote(.F), SpelledNote(.F, accidental: 1), SpelledNote(.G),
        SpelledNote(.A, accidental: -1), SpelledNote(.A), SpelledNote(.B, accidental: -1), SpelledNote(.B),
    ]

    /// Parses a note at the start of `text`, returning it and the unparsed remainder.
    /// Accidentals are consumed greedily; callers that need another split can use `parsePrefixes`.
    static func parsePrefix(_ text: Substring) -> (SpelledNote, Substring)? {
        parsePrefixes(text).first
    }

    /// Every way of reading a note at the start of `text`, longest accidental first.
    /// `"Cb5"` gives both `(C♭, "5")` and `(C, "b5")`.
    static func parsePrefixes(_ text: Substring) -> [(SpelledNote, Substring)] {
        guard let first = text.first, let letter = Letter(first) else {
            return []
        }

        var results: [(SpelledNote, Substring)] = [(SpelledNote(letter), text.dropFirst())]
        var accidental = 0
        var rest = text.dropFirst()

        while let symbol = rest.first {
            switch symbol {
            case "#", "♯": accidental += 1
            case "b", "♭": accidental -= 1
            case "x", "𝄪": accidental += 2
            case "𝄫": accidental -= 2
            default: return results.reversed()
            }
            rest = rest.dropFirst()
            results.append((SpelledNote(letter, accidental: accidental), rest))
        }

        return results.reversed()
    }
}

extension SpelledNote: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let note = SpelledNote(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid note \"\(string)\"")
        }
        self = note
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(asciiDescription)
    }
}
