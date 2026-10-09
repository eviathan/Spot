//
//  Tuning.swift
//  SpotCore
//

import Foundation

/// Open-string pitches for a fretted instrument, lowest string first.
public struct Tuning: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    /// MIDI note numbers, lowest string first. Encoded as names like `"E2"`.
    public var strings: [Int]

    public init(id: String, name: String, strings: [Int]) {
        self.id = id
        self.name = name
        self.strings = strings
    }

    public static let standard = Tuning(id: "guitar.standard", name: "Standard", strings: [40, 45, 50, 55, 59, 64])
    public static let dropD = Tuning(id: "guitar.drop-d", name: "Drop D", strings: [38, 45, 50, 55, 59, 64])
    public static let dadgad = Tuning(id: "guitar.dadgad", name: "DADGAD", strings: [38, 45, 50, 55, 57, 62])
    public static let openG = Tuning(id: "guitar.open-g", name: "Open G", strings: [38, 43, 50, 55, 59, 62])
    public static let sevenString = Tuning(id: "guitar.standard-7", name: "Standard 7-string", strings: [35, 40, 45, 50, 55, 59, 64])
    public static let bass = Tuning(id: "bass.standard", name: "Bass", strings: [28, 33, 38, 43])
    public static let fiveStringBass = Tuning(id: "bass.standard-5", name: "5-string bass", strings: [23, 28, 33, 38, 43])

    public static let presets: [Tuning] = [standard, dropD, dadgad, openG, sevenString, bass, fiveStringBass]

    /// `"E2"` for MIDI 40 (middle C is C4 = 60).
    public static func noteName(midi: Int) -> String {
        SpelledNote.conventional(PitchClass(midi)).asciiDescription + String(midi / 12 - 1)
    }

    /// Parses `"E2"`, `"Bb1"`, `"C#-1"`.
    public static func midiNote(named name: String) -> Int? {
        guard let (note, rest) = SpelledNote.parsePrefix(Substring(name)), let octave = Int(rest) else {
            return nil
        }
        // Use the natural letter's octave so B#3 is C4 and Cb4 is B3
        return (octave + 1) * 12 + note.letter.naturalPitchClass.value + note.accidental
    }

    enum CodingKeys: String, CodingKey {
        case id, name, strings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        strings = try container.decode([String].self, forKey: .strings).map { name in
            guard let midi = Tuning.midiNote(named: name) else {
                throw DecodingError.dataCorruptedError(forKey: .strings, in: container, debugDescription: "Invalid note \"\(name)\"")
            }
            return midi
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(strings.map(Tuning.noteName(midi:)), forKey: .strings)
    }
}
