//
//  Key.swift
//  SpotCore
//

import Foundation

public enum KeyQuality: String, Codable, Sendable {
    case major
    case minor

    // Parsed once: the analysis asks for these thousands of times
    private static let majorFormula = Formula("1 2 3 4 5 6 7")!
    private static let minorFormula = Formula("1 2 b3 4 5 b6 b7")!

    var formula: Formula {
        switch self {
        case .major: return KeyQuality.majorFormula
        case .minor: return KeyQuality.minorFormula
        }
    }

    /// How to spell the five pitch classes outside the key, by semitones above the tonic.
    /// Major keys borrow b2 b3 #4 b6 b7; minor keys use b2 3 #4 6 7.
    var chromaticDegrees: [Int: Degree] {
        switch self {
        case .major:
            return [1: Degree("b2")!, 3: Degree("b3")!, 6: Degree("#4")!, 8: Degree("b6")!, 10: Degree("b7")!]
        case .minor:
            return [1: Degree("b2")!, 4: Degree("3")!, 6: Degree("#4")!, 9: Degree("6")!, 11: Degree("7")!]
        }
    }
}

/// A key used to spell notes, so D major shows F♯ and C♯ rather than G♭ and D♭.
public struct Key: Hashable, Codable, Sendable, CustomStringConvertible {
    public let tonic: SpelledNote
    public let quality: KeyQuality

    public init(_ tonic: SpelledNote, _ quality: KeyQuality) {
        self.tonic = tonic
        self.quality = quality
    }

    /// The key with the usual tonic spelling for this pitch class, e.g. B♭ major, F♯ minor.
    public init(conventional pitchClass: PitchClass, _ quality: KeyQuality) {
        self.init(Key.conventionalTonic(pitchClass, quality), quality)
    }

    public static func conventionalTonic(_ pitchClass: PitchClass, _ quality: KeyQuality) -> SpelledNote {
        switch quality {
        case .major:
            return SpelledNote.conventional(pitchClass)
        case .minor:
            // Minor keys prefer C♯, G♯ over D♭, A♭; E♭ minor (6♭) over D♯ minor (6♯)
            let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
            return SpelledNote(names[pitchClass.value])!
        }
    }

    public var scale: [SpelledNote] {
        quality.formula.spelled(from: tonic)
    }

    /// Spells any pitch class in this key: diatonic notes use the key's spelling,
    /// chromatic ones use the nearest common alteration.
    public func spell(_ pitchClass: PitchClass) -> SpelledNote {
        if let diatonic = scale.first(where: { $0.pitchClass == pitchClass }) {
            return diatonic
        }
        let offset = pitchClass.semitones(above: tonic.pitchClass)
        return tonic.spelling(quality.chromaticDegrees[offset]!)
    }

    public var description: String {
        "\(tonic) \(quality.rawValue)"
    }
}
