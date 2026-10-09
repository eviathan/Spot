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

    private(set) var bpm: Int = 120
    var beatsPerBar = 4
    private(set) var isPlaying = false
    var isRecording = false
    var isLooping = false
    var isMetronomeOn = false

    /// While playing, `anchorBeat` was (or will be, during a count-in) the position at `anchorHostTime`.
    private(set) var anchorBeat: Double = 0
    private(set) var anchorHostTime: UInt64 = 0

    var clock: TempoClock {
        TempoClock(bpm: Double(bpm), beatsPerBar: beatsPerBar)
    }

    /// Position in beats; negative during a count-in, 0 when stopped.
    func position(at hostTime: UInt64 = HostTime.now) -> Double {
        guard isPlaying else { return 0 }
        return anchorBeat + clock.beats(forSeconds: HostTime.seconds(from: anchorHostTime, to: hostTime))
    }

    /// When the given beat happens (or happened).
    func hostTime(forBeat beat: Double) -> UInt64 {
        HostTime.adding(clock.seconds(forBeats: beat - anchorBeat), to: anchorHostTime)
    }

    func start(atBeat beat: Double, hostTime: UInt64) {
        anchorBeat = beat
        anchorHostTime = hostTime
        isPlaying = true
    }

    func stop() {
        isPlaying = false
        anchorBeat = 0
    }

    func incrementBPM(_ amount: Int) {
        let newBPM = min(max(bpm + amount, TransportState.bpmRange.lowerBound), TransportState.bpmRange.upperBound)
        guard newBPM != bpm else { return }

        // Keep the position continuous: re-anchor at the current beat before the tempo changes
        if isPlaying {
            let now = HostTime.now
            anchorBeat = position(at: now)
            anchorHostTime = now
        }
        bpm = newBPM
    }
}
