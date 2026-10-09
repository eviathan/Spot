//
//  TransportState.swift
//  Spot
//

import Foundation
import Observation

/// Playback controls. UI-only until the audio engine exists (Plan.md, step 5).
@Observable
final class TransportState {
    static let bpmRange = 1...999

    private(set) var bpm: Int = 120
    var isPlaying = false
    var isRecording = false
    var isLooping = false
    var isMetronomeOn = false

    func incrementBPM(_ amount: Int) {
        bpm = min(max(bpm + amount, TransportState.bpmRange.lowerBound), TransportState.bpmRange.upperBound)
    }
}
