//
//  TempoClock.swift
//  SpotCore
//

import Foundation

/// Converts between musical time (beats) and seconds at a fixed tempo.
public struct TempoClock: Hashable, Sendable {
    public var bpm: Double
    public var beatsPerBar: Int

    public init(bpm: Double, beatsPerBar: Int = 4) {
        self.bpm = bpm
        self.beatsPerBar = beatsPerBar
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

    /// 1-based bar and beat for a position, e.g. beat 5 in 4/4 is bar 2, beat 2.
    /// Count-in positions (negative beats) give bars 0, -1, ...
    public func barAndBeat(_ position: Double) -> (bar: Int, beat: Int) {
        let whole = Int(floor(position))
        let bar = Int(floor(Double(whole) / Double(beatsPerBar)))
        let beat = whole - bar * beatsPerBar
        return (bar + 1, beat + 1)
    }
}

/// A metronome click at a whole beat.
public struct Click: Hashable, Sendable {
    public var beat: Int
    /// First beat of the bar.
    public var isAccent: Bool
}

public enum Metronome {
    /// The clicks with beats in `from..<to` (positions in beats, negative during a count-in).
    public static func clicks(from: Double, to: Double, beatsPerBar: Int) -> [Click] {
        guard to > from else { return [] }
        let first = Int(ceil(from))
        let last = Int(ceil(to)) - 1
        guard first <= last else { return [] }
        return (first...last).map { beat in
            Click(beat: beat, isAccent: ((beat % beatsPerBar) + beatsPerBar) % beatsPerBar == 0)
        }
    }
}
