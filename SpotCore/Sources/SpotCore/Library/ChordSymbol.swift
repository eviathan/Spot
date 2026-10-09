//
//  ChordSymbol.swift
//  SpotCore
//

import Foundation

/// A concrete chord such as `B♭7♯9/D`: root, chord definition and optional bass note.
public struct ChordSymbol: Hashable, Sendable, CustomStringConvertible {
    public var root: SpelledNote
    public var chord: ChordDefinition
    public var bass: SpelledNote?

    public init(root: SpelledNote, chord: ChordDefinition, bass: SpelledNote? = nil) {
        self.root = root
        self.chord = chord
        self.bass = bass
    }

    /// Chord tones spelled from the root (B♭7 → B♭ D F A♭). The bass is not included.
    public var tones: [SpelledNote] {
        chord.formula.spelled(from: root)
    }

    public var description: String {
        root.description + chord.displaySymbol + (bass.map { "/" + $0.description } ?? "")
    }

    /// Plain-text form that `ChordSymbolParser` reads back.
    public var asciiDescription: String {
        root.asciiDescription + chord.displaySymbol + (bass.map { "/" + $0.asciiDescription } ?? "")
    }
}

/// Parses chord symbols (`"C"`, `"F#m7b5"`, `"Bb7#9/D"`, `"C6/9"`) against a set of chord definitions.
public struct ChordSymbolParser: Sendable {
    private let chordsBySymbol: [String: ChordDefinition]

    public init(chords: [ChordDefinition]) {
        var table: [String: ChordDefinition] = [:]
        for chord in chords {
            for symbol in chord.symbols where table[symbol] == nil {
                table[symbol] = chord
            }
        }
        chordsBySymbol = table
    }

    public func parse(_ text: String) -> ChordSymbol? {
        let trimmed = Substring(text.trimmingCharacters(in: .whitespaces))

        // A root accidental can be ambiguous ("Cb5" is C♭5 or C(♭5)), so try each reading
        for (root, rest) in SpelledNote.parsePrefixes(trimmed) {
            if let symbol = parseQualityAndBass(root: root, text: rest) {
                return symbol
            }
        }

        return nil
    }

    private func parseQualityAndBass(root: SpelledNote, text: Substring) -> ChordSymbol? {
        // Symbols can contain "/" themselves ("6/9", "m/Maj7"), so try the whole remainder first
        if let chord = chordsBySymbol[String(text)] {
            return ChordSymbol(root: root, chord: chord)
        }

        guard let slash = text.lastIndex(of: "/"),
              let bass = SpelledNote(String(text[text.index(after: slash)...])),
              let chord = chordsBySymbol[String(text[..<slash])] else {
            return nil
        }

        return ChordSymbol(root: root, chord: chord, bass: bass)
    }
}
