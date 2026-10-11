//
//  TransportState.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

/// Playback position and tempo. `PlaybackController` starts and stops it; views read the position.
@Observable
final class TransportState {
    static let bpmRange = 1...999

    /// Not rounded: a sequence's tempo can be fractional, and the clock has to match its audio exactly.
    private(set) var bpm: Double = 120
    /// Any time signature; beats (the tempo, positions) stay quarter notes.
    var timeSignature = TimeSignature(4, 4)
    /// The beat bar 1 starts on (a sequence's start marker): bars, and the metronome's accents, count from here.
    var barOrigin: Double = 0
    /// While a tab plays (its clock counts seconds, not beats), how to show the position as "bar.beat".
    @ObservationIgnored var positionLabel: ((Double) -> String)?
    private(set) var isPlaying = false
    var isRecording = false
    var isMetronomeOn = false

    /// While playing, `anchorBeat` was (or will be, during a count-in) the position at `anchorHostTime`.
    private(set) var anchorBeat: Double = 0
    private(set) var anchorHostTime: UInt64 = 0
    /// The timing before a jump that hasn't happened yet (jumps are set up just ahead of time).
    private var anchorBeforeJump: (beat: Double, hostTime: UInt64)?

    var clock: TempoClock {
        TempoClock(bpm: bpm, timeSignature: timeSignature)
    }

    /// Position in beats; negative during a count-in, 0 when stopped.
    func position(at hostTime: UInt64 = HostTime.now) -> Double {
        guard isPlaying else { return 0 }
        if let before = anchorBeforeJump, hostTime < anchorHostTime {
            return before.beat + clock.beats(forSeconds: HostTime.seconds(from: before.hostTime, to: hostTime))
        }
        return anchorBeat + clock.beats(forSeconds: HostTime.seconds(from: anchorHostTime, to: hostTime))
    }

    /// When the given beat happens (or happened).
    func hostTime(forBeat beat: Double) -> UInt64 {
        HostTime.adding(clock.seconds(forBeats: beat - anchorBeat), to: anchorHostTime)
    }

    func start(atBeat beat: Double, hostTime: UInt64) {
        anchorBeforeJump = nil
        anchorBeat = beat
        anchorHostTime = hostTime
        isPlaying = true
    }

    /// Moves the playhead while playing, e.g. back to the start of a loop at the moment it ends.
    func jump(toBeat beat: Double, atHostTime hostTime: UInt64) {
        anchorBeforeJump = (anchorBeat, anchorHostTime)
        anchorBeat = beat
        anchorHostTime = hostTime
    }
    
    func setBPM(_ value: Double) {
        let newBPM = min(max(value, Double(TransportState.bpmRange.lowerBound)), Double(TransportState.bpmRange.upperBound))
        guard newBPM != bpm else { return }

        // Keep the position continuous: re-anchor at the current beat before the tempo changes
        if isPlaying {
            let now = HostTime.now
            anchorBeat = position(at: now)
            anchorHostTime = now
        }
        bpm = newBPM
    }

    func stop() {
        isPlaying = false
        anchorBeat = 0
    }

    /// Steps to the next whole bpm up or down.
    func incrementBPM(_ amount: Int) {
        setBPM(bpm.rounded() + Double(amount))
    }
}
