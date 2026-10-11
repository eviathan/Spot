//
//  TempoClock.swift
//  SpotCore
//

import Foundation

/// Converts between musical time (beats) and seconds at a fixed tempo.
/// Beats are quarter notes (the tempo counts them); bars and the count go by the time signature.
public struct TempoClock: Hashable, Sendable {
    public var bpm: Double
    public var timeSignature: TimeSignature

    public init(bpm: Double, timeSignature: TimeSignature = TimeSignature(4, 4)) {
        self.bpm = bpm
        self.timeSignature = timeSignature
    }

    public init(bpm: Double, beatsPerBar: Int) {
        self.init(bpm: bpm, timeSignature: TimeSignature(beatsPerBar, 4))
    }

    public var secondsPerBeat: Double {
        60 / bpm
    }

    public func seconds(forBeats beats: Double) -> Double {
        beats * secondsPerBeat
    }

    public func beats(forSeconds seconds: Double) -> Double {
        seconds / secondsPerBeat
    }

    /// 1-based bar and beat for a position (in quarter notes), the beat counted in the time signature's unit:
    /// beat 5 in 4/4 is bar 2, beat 2; in 6/8 position 1.5 is bar 1, beat 4. Count-in positions (negative) give
    /// bars 0, -1, ...
    public func barAndBeat(_ position: Double) -> (bar: Int, beat: Int) {
        let count = Int(floor(position / timeSignature.countUnit + 1e-9))
        let numerator = max(timeSignature.numerator, 1)
        let bar = Int(floor(Double(count) / Double(numerator)))
        return (bar + 1, count - bar * numerator + 1)
    }
}

/// A metronome click, on a beat of the time signature's unit.
public struct Click: Hashable, Sendable {
    /// Where, in quarter notes.
    public var beat: Double
    /// First beat of the bar.
    public var isAccent: Bool
}

public enum Metronome {
    /// The clicks between `from` and `to` (positions in quarter notes, negative during a count-in): one per beat
    /// of the time signature (eighths in 6/8), the first of each bar accented.
    public static func clicks(from: Double, to: Double, timeSignature: TimeSignature) -> [Click] {
        guard to > from else { return [] }
        let unit = timeSignature.countUnit
        let numerator = max(timeSignature.numerator, 1)
        let first = Int(ceil(from / unit - 1e-9))
        let last = Int(ceil(to / unit - 1e-9)) - 1
        guard first <= last else { return [] }
        return (first...last).map { count in
            Click(beat: Double(count) * unit, isAccent: ((count % numerator) + numerator) % numerator == 0)
        }
    }

    public static func clicks(from: Double, to: Double, beatsPerBar: Int) -> [Click] {
        clicks(from: from, to: to, timeSignature: TimeSignature(beatsPerBar, 4))
    }
}
