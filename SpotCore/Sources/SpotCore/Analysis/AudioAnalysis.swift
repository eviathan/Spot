//
//  AudioAnalysis.swift
//  SpotCore
//

import Foundation

/// What was heard in a recording: tempo, beats, where bar 1 is, chords and key.
/// Kept with its features so a different tempo or bar 1 can be tried without starting over.
public struct AudioAnalysis: Sendable {
    public let features: AnalysisFeatures
    public let tempoCandidates: [TempoCandidate]
    public let beatsPerBar: Int
    /// The tempo the beats were tracked at.
    public private(set) var trackedTempo: Double
    /// Beat times in seconds.
    public private(set) var beats: [Double]
    /// The first beat (index into `beats`) that starts a bar.
    public private(set) var downbeat: Int
    public private(set) var chords: [DetectedChord]
    public let key: Key?

    /// Analyses a recording. Calls `progress` with 0...1 and stops if it returns false.
    public static func analyse(_ audio: AudioData, beatsPerBar: Int, progress: (Double) -> Bool = { _ in true }) -> AudioAnalysis? {
        guard let features = AnalysisFeatures.compute(audio, progress: { progress($0 * 0.85) }) else { return nil }
        let candidates = BeatTracker.tempoCandidates(features)
        guard let tempo = candidates.first?.bpm else { return nil }
        let key = KeyFinder.key(features.chroma)
        var analysis = AudioAnalysis(features: features, tempoCandidates: candidates, beatsPerBar: beatsPerBar,
                                     trackedTempo: tempo, beats: [], downbeat: 0, chords: [], key: key)
        analysis.track(tempo: tempo)
        _ = progress(1)
        return analysis
    }

    /// Re-tracks the beats at another tempo (e.g. double or half), working bar 1 and the chords out again.
    public mutating func track(tempo: Double) {
        trackedTempo = tempo
        beats = BeatTracker.beats(features, bpm: tempo)
        let chroma = ChordRecognizer.beatChroma(features, beats: beats)
        downbeat = BeatTracker.downbeatPhase(features, beats: beats, beatsPerBar: beatsPerBar, chroma: chroma)
        chords = ChordRecognizer.recognise(chroma, beatsPerBar: beatsPerBar, downbeat: downbeat)
    }

    /// Moves bar 1 by a number of beats (when the guess is off by a beat or two).
    public mutating func shiftDownbeat(by beats: Int) {
        downbeat = ((downbeat + beats) % beatsPerBar + beatsPerBar) % beatsPerBar
        let chroma = ChordRecognizer.beatChroma(features, beats: self.beats)
        chords = ChordRecognizer.recognise(chroma, beatsPerBar: beatsPerBar, downbeat: downbeat)
    }

    /// The average tempo of the tracked beats (over the whole run, so frame rounding averages out).
    public var tempo: Double {
        guard beats.count > 1, let first = beats.first, let last = beats.last, last > first else { return trackedTempo }
        return 60 * Double(beats.count - 1) / (last - first)
    }

    /// Grid beat for a tracked beat: bar 1 starts at the first downbeat. Beats before it (a pickup) are negative.
    public func gridBeat(_ index: Int) -> Double {
        Double(index - downbeat)
    }

    /// A warp marker on every downbeat, so the grid follows the band.
    public var warpMarkers: [WarpMarker] {
        stride(from: downbeat, to: beats.count, by: beatsPerBar).map { index in
            WarpMarker(sourceTime: beats[index], beat: gridBeat(index))
        }
    }

    /// Bars needed to hold every tracked beat after bar 1.
    public var lengthInBars: Int {
        max(1, Int(ceil(Double(beats.count - downbeat) / Double(beatsPerBar))))
    }

    /// The chords on the grid, as (beat range, symbol). Chords before bar 1 and "no chord" runs are left out.
    public func chordRegions(key: Key?) -> [(range: BeatRange, symbol: String)] {
        chords.compactMap { chord in
            guard let symbol = chord.symbol(in: key ?? self.key) else { return nil }
            let start = max(0, gridBeat(chord.beats.lowerBound)), end = gridBeat(chord.beats.upperBound)
            return end > start ? (BeatRange(start, end), symbol) : nil
        }
    }
}
