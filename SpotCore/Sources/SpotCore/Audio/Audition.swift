//
//  Audition.swift
//  SpotCore
//

import Foundation

/// A note to play, in seconds from when playback starts.
public struct NoteEvent: Hashable, Sendable {
    /// MIDI note number (60 = middle C).
    public var note: Int
    public var velocity: Int
    public var time: Double
    public var duration: Double

    public init(note: Int, velocity: Int = 90, time: Double, duration: Double) {
        self.note = note
        self.velocity = velocity
        self.time = time
        self.duration = duration
    }
}

/// Turns notes on the instrument into something to listen to.
public enum Audition {
    /// The pitches of placed notes, low to high, without repeats.
    public static func pitches(_ positions: some Sequence<FretPosition>, on fretboard: Fretboard) -> [Int] {
        Array(Set(positions.map(fretboard.midiNote(at:)))).sorted()
    }

    /// All notes together, strummed low to high.
    public static func chord(_ pitches: [Int], strum: Double = 0.03, duration: Double = 1.6, velocity: Int = 90) -> [NoteEvent] {
        pitches.enumerated().map { index, note in
            let start = Double(index) * strum
            return NoteEvent(note: note, velocity: velocity, time: start, duration: duration - start)
        }
    }

    /// One note after another, up and (optionally) back down without repeating the top note.
    public static func sequence(_ pitches: [Int], noteLength: Double, upAndDown: Bool = true, velocity: Int = 90) -> [NoteEvent] {
        let order = upAndDown && pitches.count > 1 ? pitches + pitches.dropLast().reversed() : pitches
        return order.enumerated().map { index, note in
            // Slightly shorter than the gap so repeated notes re-trigger cleanly
            NoteEvent(note: note, velocity: velocity, time: Double(index) * noteLength, duration: noteLength * 0.9)
        }
    }

    /// How a shape should be heard: chords strummed, scales and arpeggios played in eighth notes.
    public static func events(for shape: Shape, placement: [FretPosition: ShapeNote], on fretboard: Fretboard,
                              clock: TempoClock) -> [NoteEvent] {
        let pitches = self.pitches(placement.keys, on: fretboard)
        switch shape.kind {
        case .chord: return chord(pitches, duration: max(1.2, clock.seconds(forBeats: 2)))
        case .scale: return sequence(pitches, noteLength: clock.seconds(forBeats: 0.5))
        }
    }
}
