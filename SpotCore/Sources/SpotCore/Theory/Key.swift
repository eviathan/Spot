//
//  Key.swift
//  SpotCore
//

import Foundation

/// Major, minor, or one of the other modes of the major scale (a song in B Dorian, D Mixolydian…).
public enum KeyQuality: String, Codable, Sendable, CaseIterable {
    case major
    case minor
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case locrian

    // Parsed once: the analysis asks for these thousands of times
    private static let formulas: [KeyQuality: Formula] = [
        .major: Formula("1 2 3 4 5 6 7")!,
        .minor: Formula("1 2 b3 4 5 b6 b7")!,
        .dorian: Formula("1 2 b3 4 5 6 b7")!,
        .phrygian: Formula("1 b2 b3 4 5 b6 b7")!,
        .lydian: Formula("1 2 3 #4 5 6 7")!,
        .mixolydian: Formula("1 2 3 4 5 6 b7")!,
        .locrian: Formula("1 b2 b3 4 b5 b6 b7")!,
    ]

    /// How notes outside the key are spelled, by semitones above the tonic: as the nearest common alteration
    /// (a major key borrows b2 b3 #4 b6 b7; a minor key uses b2 3 #4 6 7). Only those outside a mode are used.
    private static let chromatic: [Int: Degree] = [
        1: Degree("b2")!, 2: Degree("2")!, 3: Degree("b3")!, 4: Degree("3")!, 5: Degree("4")!, 6: Degree("#4")!,
        7: Degree("5")!, 8: Degree("b6")!, 9: Degree("6")!, 10: Degree("b7")!, 11: Degree("7")!,
    ]

    public var formula: Formula {
        KeyQuality.formulas[self]!
    }

    var chromaticDegrees: [Int: Degree] {
        KeyQuality.chromatic
    }

    /// "major", "minor", "Dorian"…
    public var name: String {
        switch self {
        case .major, .minor: return rawValue
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// After the tonic in a short key name: "B", "Bm", "B dor".
    public var shortSuffix: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        default: return " " + rawValue.prefix(3)
        }
    }

    /// Minor-sounding (a minor third above the tonic).
    public var isMinor: Bool {
        formula.pitchClassOffsets.contains(3)
    }

    /// The built-in scale with the key's notes.
    public var scaleId: String {
        switch self {
        case .major: return "builtin.scale.major"
        case .minor: return "builtin.scale.natural-minor"
        default: return "builtin.scale." + rawValue
        }
    }

    /// The key for a scale with exactly a key's notes, if it's one.
    public init?(scaleId: String) {
        guard let quality = KeyQuality.allCases.first(where: { $0.scaleId == scaleId }) else { return nil }
        self = quality
    }

    /// Semitones above the major key with the same notes (its key signature): Dorian is the major scale from
    /// its second note, and so on.
    var semitonesAboveRelativeMajor: Int {
        switch self {
        case .major: return 0
        case .dorian: return 2
        case .phrygian: return 4
        case .lydian: return 5
        case .mixolydian: return 7
        case .minor: return 9
        case .locrian: return 11
        }
    }

    /// Which note of its relative major the tonic is.
    var degreeOfRelativeMajor: Int {
        switch self {
        case .major: return 0
        case .dorian: return 1
        case .phrygian: return 2
        case .lydian: return 3
        case .mixolydian: return 4
        case .minor: return 5
        case .locrian: return 6
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
        default:
            // As the note it is in its relative major's key signature (B Dorian has A major's two sharps)
            let relative = Key(conventional: pitchClass.transposed(by: -quality.semitonesAboveRelativeMajor), .major)
            return relative.scale[quality.degreeOfRelativeMajor]
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
        let spelled = tonic.spelling(quality.chromaticDegrees[offset]!)
        // Outside the key, a white note reads as itself, not E♯, B♯, C♭ or F♭ (F in B minor, not E♯)
        if let natural = SpelledNote(["C", "", "D", "", "E", "F", "", "G", "", "A", "", "B"][pitchClass.value]),
           spelled.description != natural.description {
            return natural
        }
        return spelled
    }

    public var description: String {
        "\(tonic) \(quality.name)"
    }

    /// "B", "Bm", "B dor".
    public var shortName: String {
        "\(tonic)\(quality.shortSuffix)"
    }
}
