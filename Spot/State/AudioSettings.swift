//
//  AudioSettings.swift
//  Spot
//

import Foundation
import Observation
import CoreMIDI

/// MIDI and metronome preferences. Saved between launches.
@Observable
final class AudioSettings {
    /// Also send straight to this MIDI destination; nil for the "Spot" virtual source only.
    var midiDestinationID: MIDIUniqueID? {
        didSet { defaults.set(midiDestinationID.map { Int($0) }, forKey: "audio.midiDestinationID") }
    }
    /// 1–16.
    var midiChannel: Int {
        didSet { defaults.set(midiChannel, forKey: "audio.midiChannel") }
    }
    var previewVelocity: Int {
        didSet { defaults.set(previewVelocity, forKey: "audio.previewVelocity") }
    }
    /// 0–1.
    var metronomeVolume: Double {
        didSet { defaults.set(metronomeVolume, forKey: "audio.metronomeVolume") }
    }
    /// Bars of clicks before beat 1 when playback starts.
    var countInBars: Int {
        didSet { defaults.set(countInBars, forKey: "audio.countInBars") }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        midiDestinationID = (defaults.object(forKey: "audio.midiDestinationID") as? Int).map { MIDIUniqueID($0) }
        midiChannel = defaults.object(forKey: "audio.midiChannel") as? Int ?? 1
        previewVelocity = defaults.object(forKey: "audio.previewVelocity") as? Int ?? 90
        metronomeVolume = defaults.object(forKey: "audio.metronomeVolume") as? Double ?? 0.7
        countInBars = defaults.object(forKey: "audio.countInBars") as? Int ?? 1
    }
}
