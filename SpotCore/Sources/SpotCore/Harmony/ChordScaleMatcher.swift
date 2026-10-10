//
//  ChordScaleMatcher.swift
//  SpotCore
//

import Foundation

/// What a note does over a chord, given the scale being played.
public enum NoteRole: String, Sendable {
    case chordTone
    /// A scale note that adds colour without clashing.
    case tension
    /// A scale note a half step above a chord tone, which rubs against it if held.
    case avoid
    /// Not in the scale.
    case outside
}

/// A scale to play over a chord, rooted on the chord's root.
public struct ScaleSuggestion: Identifiable, Hashable, Sendable {
    public var scale: ScaleDefinition
    public var score: Double
    /// Short reasons for the ranking, e.g. "Fits C major", "Avoid: 4".
    public var reasons: [String]
    public var avoidNotes: [Degree]
    public var tensions: [Degree]

    public var id: String { scale.id }
}

/// An arpeggio to play over a chord.
public struct ArpeggioSuggestion: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case chord
        case guideTones
        case upperStructure
    }

    public var kind: Kind
    /// Semitones from the chord root to the arpeggio's root.
    public var rootOffset: Int
    /// The arpeggio's notes from its own root.
    public var formula: Formula
    /// The library chord it spells, if any (e.g. Em7 over Cmaj7).
    public var chord: ChordDefinition?
    /// The arpeggio's notes as degrees of the underlying chord, e.g. 3 5 7 9.
    public var degreesOverChord: [Degree]

    public var id: String {
        "\(kind.rawValue):\(rootOffset):\(formula)"
    }
}

/// Optional surroundings that change which scale fits best.
public struct ChordContext: Sendable {
    public var key: Key?
    /// The scale played over the previous chord, and that chord's root.
    public var previous: (scale: ScaleDefinition, root: PitchClass)?

    public init(key: Key? = nil, previous: (scale: ScaleDefinition, root: PitchClass)? = nil) {
        self.key = key
        self.previous = previous
    }
}

public enum ChordScaleMatcher {

    // MARK: - Scales

    /// Scales that contain every required note of the chord, best first.
    public static func scales(for chord: ChordDefinition, root: PitchClass, among scales: [ScaleDefinition],
                              context: ChordContext = ChordContext()) -> [ScaleSuggestion] {
        let required = Set(chord.requiredDegrees.map(\.pitchClassOffset))
        let keyPitches = context.key.map { key in Set(key.scale.map(\.pitchClass)) }
        let previousPitches = context.previous.map { Set($0.scale.formula.pitchClasses(from: $0.root)) }

        return scales
            .filter { required.isSubset(of: $0.formula.pitchClassOffsets) && $0.formula.pitchClassOffsets.count < 12 }
            .map { scale in
                let roles = self.roles(chord: chord, scale: scale)
                let avoid = degrees(of: scale, where: { roles[$0] == .avoid })
                let tensions = degrees(of: scale, where: { roles[$0] == .tension })
                let pitches = Set(scale.formula.pitchClasses(from: root))

                var score = commonness(scale)
                var reasons: [String] = []

                if let keyPitches, let key = context.key {
                    if pitches.isSubset(of: keyPitches) {
                        score += 3
                        reasons.append("Fits \(key)")
                    } else {
                        let outside = pitches.subtracting(keyPitches).sorted().map { key.spell($0).description }
                        score -= 0.5 * Double(outside.count)
                        reasons.append("Outside the key: \(outside.joined(separator: " "))")
                    }
                }

                if avoid.isEmpty {
                    reasons.append("No avoid notes")
                } else {
                    score -= 0.5 * Double(avoid.count)
                    reasons.append("Avoid: \(avoid.map(\.prettyDescription).joined(separator: " "))")
                }

                if let previousPitches {
                    let changed = pitches.symmetricDifference(previousPitches).count / 2
                    score -= 0.6 * Double(changed)
                    reasons.append(changed == 0 ? "Same notes as the last chord" : "\(changed) note\(changed == 1 ? "" : "s") change from the last chord")
                }

                return ScaleSuggestion(scale: scale, score: score, reasons: reasons, avoidNotes: avoid, tensions: tensions)
            }
            .sorted { ($0.score, commonness($0.scale)) > ($1.score, commonness($1.scale)) }
    }

    /// The role of each of the 12 pitch classes (as semitones above the chord root) when playing `scale` over `chord`.
    public static func roles(chord: ChordDefinition, scale: ScaleDefinition) -> [Int: NoteRole] {
        let chordTones = chord.formula.pitchClassOffsets
        let scaleTones = scale.formula.pitchClassOffsets
        // Only chord tones that are actually in the scale can be clashed with (the altered scale drops the 5th)
        let soundingChordTones = chordTones.intersection(scaleTones)
        let isDominant = chordTones.contains(4) && chordTones.contains(10)

        var roles: [Int: NoteRole] = [:]
        for offset in 0..<12 {
            if chordTones.contains(offset) {
                roles[offset] = .chordTone
            } else if !scaleTones.contains(offset) {
                roles[offset] = .outside
            } else if soundingChordTones.contains(where: { PitchClass(offset - $0).value == 1 })
                        && !(isDominant && offset == 1) {
                // A half step above a chord tone; ♭9 over a dominant chord is a standard tension
                roles[offset] = .avoid
            } else {
                roles[offset] = .tension
            }
        }
        return roles
    }

    /// How often a scale is the go-to choice, as a starting point for ranking.
    static func commonness(_ scale: ScaleDefinition) -> Double {
        let id = scale.id.replacingOccurrences(of: "builtin.scale.", with: "")
        switch id {
        case "major", "dorian", "mixolydian", "natural-minor": return 3
        case "lydian", "lydian-dominant", "altered", "aeolian-b5", "major-pentatonic", "minor-pentatonic": return 2.5
        case "phrygian", "locrian", "melodic-minor", "harmonic-minor", "phrygian-dominant", "blues",
             "half-whole-diminished", "whole-half-diminished": return 2
        case "mixolydian-b6", "lydian-augmented", "whole-tone", "major-blues",
             "bebop-dominant", "bebop-major", "bebop-dorian": return 1.5
        default: return scale.id.hasPrefix("builtin.") ? 0.5 : 1
        }
    }

    private static func degrees(of scale: ScaleDefinition, where include: (Int) -> Bool) -> [Degree] {
        scale.formula.degrees.filter { include($0.pitchClassOffset) }.map(tensionName)
    }

    /// Non-chord scale notes are named as extensions: 2 → 9, 4 → 11, 6 → 13.
    public static func tensionName(_ degree: Degree) -> Degree {
        [2, 4, 6].contains(degree.number) ? Degree(degree.number + 7, accidental: degree.accidental) : degree
    }

    // MARK: - Arpeggios

    /// The chord's own arpeggio, its guide tones, and upper-structure arpeggios from `scale`
    /// (chords built on other scale degrees that add tensions without avoid notes).
    public static func arpeggios(for chord: ChordDefinition, scale: ScaleDefinition?, chords: [ChordDefinition]) -> [ArpeggioSuggestion] {
        var result = [ArpeggioSuggestion(kind: .chord, rootOffset: 0, formula: chord.formula, chord: chord,
                                         degreesOverChord: chord.formula.degrees)]

        let third = chord.formula.degrees.first { $0.letterSteps == 2 }
        let seventh = chord.formula.degrees.first { $0.letterSteps == 6 } ?? chord.formula.degrees.first { $0.number == 6 }
        if let third, let seventh {
            result.append(ArpeggioSuggestion(kind: .guideTones, rootOffset: 0, formula: Formula([third, seventh]),
                                             chord: nil, degreesOverChord: [third, seventh]))
        }

        guard let scale else { return result }
        let roles = self.roles(chord: chord, scale: scale)
        var seen = Set<Set<Int>>()

        for size in [4, 3] {
            for diatonic in DiatonicChords.build(scale: scale.formula, size: size, chords: chords) where diatonic.scaleDegree.pitchClassOffset != 0 {
                let offsets = diatonic.scaleDegrees.map(\.pitchClassOffset)
                let addsColour = offsets.contains { roles[$0] == .tension }
                let clashes = offsets.contains { roles[$0] == .avoid }
                guard addsColour, !clashes, diatonic.chord != nil, seen.insert(Set(offsets)).inserted else { continue }

                let overChord = diatonic.scaleDegrees.map { degree in
                    roles[degree.pitchClassOffset] == .tension ? tensionName(degree) : degree
                }
                result.append(ArpeggioSuggestion(kind: .upperStructure, rootOffset: diatonic.scaleDegree.pitchClassOffset,
                                                 formula: diatonic.formula, chord: diatonic.chord,
                                                 degreesOverChord: overChord))
            }
        }
        return result
    }

    // MARK: - Keys

    /// The major or minor key that best fits a progression: most chord tones in the key,
    /// preferring keys whose tonic chord starts or ends it.
    public static func estimateKey(_ progression: [ChordSymbol]) -> Key? {
        guard !progression.isEmpty else { return nil }

        var best: (key: Key, score: Double)?
        for tonic in 0..<12 {
            for quality in [KeyQuality.major, .minor] {
                let key = Key(conventional: PitchClass(tonic), quality)
                let pitches = Set(key.scale.map(\.pitchClass))
                var score = 0.0

                for symbol in progression {
                    let tones = symbol.chord.formula.pitchClasses(from: symbol.root.pitchClass)
                    score += Double(tones.filter(pitches.contains).count) - 2 * Double(tones.filter { !pitches.contains($0) }.count)
                }

                // The tonic chord at either end is the strongest sign of the key
                let tonicChordQuality = { (symbol: ChordSymbol) -> Bool in
                    let offsets = symbol.chord.formula.pitchClassOffsets
                    return quality == .major ? offsets.contains(4) : offsets.contains(3) && !offsets.contains(4)
                }
                for (symbol, weight) in [(progression.last!, 3.0), (progression.first!, 1.5)]
                    where symbol.root.pitchClass == PitchClass(tonic) && tonicChordQuality(symbol) {
                    score += weight
                }

                if best == nil || score > best!.score {
                    best = (key, score)
                }
            }
        }
        return best?.key
    }
}

extension ShapeGenerator {
    /// The placement of one of `shapes` that best covers `target` (e.g. a chord voicing),
    /// so the scale or arpeggio sits under the same hand position.
    public static func placement(of shapes: [Shape], root: PitchClass, on fretboard: Fretboard,
                                 near target: Set<FretPosition>) -> (shape: Shape, placement: [FretPosition: ShapeNote])? {
        guard !target.isEmpty else { return nil }
        let targetCentre = Double(target.map(\.fret).reduce(0, +)) / Double(target.count)

        var best: (shape: Shape, placement: [FretPosition: ShapeNote], score: Double)?
        for shape in shapes {
            for placement in shape.placements(root: root, on: fretboard) {
                let covered = Double(target.filter { placement[$0] != nil }.count)
                let frets = placement.keys.map(\.fret)
                let centre = Double(frets.reduce(0, +)) / Double(max(frets.count, 1))
                let score = covered * 10 - abs(centre - targetCentre)
                if best == nil || score > best!.score {
                    best = (shape, placement, score)
                }
            }
        }
        return best.map { ($0.shape, $0.placement) }
    }
}
