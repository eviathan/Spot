//
//  Backing.swift
//  SpotCore
//

import Foundation

/// A note timed in beats.
public struct BeatNote: Hashable, Sendable {
    public var note: Int
    public var velocity: Int
    public var start: Double
    public var end: Double

    public init(note: Int, velocity: Int, start: Double, end: Double) {
        self.note = note
        self.velocity = velocity
        self.start = start
        self.end = end
    }
}

/// Plays a sequence's chords as a simple accompaniment.
public enum Backing {
    /// A keyboard-style voicing: a bass note (root, or the slash bass) and up to four upper notes in close
    /// position around middle C. With `previous`, picks the inversion that moves least from it.
    public static func voicing(for chord: ChordSymbol, previous: [Int]? = nil) -> (bass: Int, upper: [Int]) {
        let bassPitch = (chord.bass ?? chord.root).pitchClass
        let bass = 36 + bassPitch.value  // C2...B2

        // Upper notes: everything but the root, required tones first, at most four
        let root = chord.root.pitchClass
        var degrees = chord.chord.requiredDegrees.filter { $0.pitchClassOffset != 0 }
        degrees += chord.chord.formula.degrees.filter { $0.pitchClassOffset != 0 && !degrees.contains($0) }
        if degrees.count < 3 {
            degrees.insert(Degree(1), at: 0)  // triads and power chords keep their root on top too
        }
        var seen = Set<Int>()
        let pitchClasses = degrees
            .map { root.transposed(by: $0.semitones).value }
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .sorted()

        // Every inversion in close position, in each octave that puts its lowest note between E3 and E4
        let candidates: [[Int]] = pitchClasses.indices.flatMap { rotation in
            let ordered = Array(pitchClasses[rotation...] + pitchClasses[..<rotation])
            return [51, 63].compactMap { floor -> [Int]? in
                var notes: [Int] = []
                for pitchClass in ordered {
                    var note = (notes.last ?? floor) + 1
                    while note % 12 != pitchClass { note += 1 }
                    notes.append(note)
                }
                return (52...64).contains(notes[0]) ? notes : nil
            }
        }

        let upper: [Int]
        if let previous, !previous.isEmpty {
            upper = candidates.min { movement(from: previous, to: $0) < movement(from: previous, to: $1) } ?? candidates[0]
        } else {
            // Without a previous chord, centre around middle C
            upper = candidates.min { abs(centre($0) - 62) < abs(centre($1) - 62) } ?? candidates[0]
        }
        return (bass, upper)
    }

    /// The backing for a whole sequence. `chords` maps each region to its parsed chord; regions that
    /// didn't parse are silent.
    public static func notes(for sequence: ChordSequence, chords: [UUID: ChordSymbol]) -> [BeatNote] {
        guard sequence.backing != .off else { return [] }
        var notes: [BeatNote] = []
        var previous: [Int]?

        for region in sequence.chords {
            guard let chord = chords[region.id] else { continue }
            let voicing = self.voicing(for: chord, previous: previous)
            previous = voicing.upper
            notes += pattern(sequence.backing, voicing: voicing, range: region.range, beatsPerBar: sequence.beatsPerBar)
        }
        return notes
    }

    private static func pattern(_ style: BackingStyle, voicing: (bass: Int, upper: [Int]), range: BeatRange,
                                beatsPerBar: Int) -> [BeatNote] {
        let gap = 0.05  // so repeated notes re-trigger
        var notes: [BeatNote] = []

        func chord(at start: Double, length: Double, velocity: Int, strum: Double = 0) {
            for (index, note) in voicing.upper.enumerated() {
                let noteStart = start + Double(index) * strum
                let end = min(start + length, range.end) - gap
                if end > noteStart {
                    notes.append(BeatNote(note: note, velocity: velocity, start: noteStart, end: end))
                }
            }
        }

        // The bass plays at the start of the chord and at each new bar, held to the next
        let barStarts = stride(from: ceil(range.start / Double(beatsPerBar)) * Double(beatsPerBar), to: range.end, by: Double(beatsPerBar))
        let bassStarts = ([range.start] + barStarts.filter { $0 > range.start })
        for (index, start) in bassStarts.enumerated() {
            let end = index + 1 < bassStarts.count ? bassStarts[index + 1] : range.end
            if style != .off {
                notes.append(BeatNote(note: voicing.bass, velocity: 85, start: start, end: end - gap))
            }
        }

        switch style {
        case .off:
            break
        case .pad:
            chord(at: range.start, length: range.length, velocity: 70)
        case .strum:
            for beat in stride(from: range.start, to: range.end, by: 1) {
                chord(at: beat, length: 1, velocity: 80, strum: 0.04)
            }
        case .comp:
            // Charleston: beat 1 and the "and" of 2 in every bar the chord covers
            let firstBar = floor(range.start / Double(beatsPerBar)) * Double(beatsPerBar)
            for bar in stride(from: firstBar, to: range.end, by: Double(beatsPerBar)) {
                for (offset, length) in [(0.0, 0.75), (1.5, 0.5)] where range.contains(bar + offset) {
                    chord(at: bar + offset, length: length, velocity: 85)
                }
            }
        }
        return notes
    }

    private static func movement(from previous: [Int], to next: [Int]) -> Int {
        // Compare voices from the bottom up; extra voices count against their nearest neighbour
        let count = max(previous.count, next.count)
        return (0..<count).reduce(0) { total, index in
            total + abs(previous[min(index, previous.count - 1)] - next[min(index, next.count - 1)])
        }
    }

    private static func centre(_ notes: [Int]) -> Int {
        notes.reduce(0, +) / max(notes.count, 1)
    }
}
