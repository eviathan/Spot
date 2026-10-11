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
    /// Record from this device; nil for the system's default input.
    var inputDeviceID: UInt32? {
        didSet { defaults.set(inputDeviceID.map { Int($0) }, forKey: "audio.inputDeviceID") }
    }
    /// Extra milliseconds to move takes earlier, on top of the latency the device reports.
    var recordingOffsetMs: Double {
        didSet { defaults.set(recordingOffsetMs, forKey: "audio.recordingOffsetMs") }
    }

    /// Play through Spot's own guitar sound (as well as over MIDI).
    var usesBuiltInSound: Bool {
        didSet { defaults.set(usesBuiltInSound, forKey: "audio.usesBuiltInSound") }
    }
    /// A SoundFont (.sf2) or DLS file to use for it (a security-scoped bookmark); nil for macOS's own instruments.
    var soundFontBookmark: Data? {
        didSet { defaults.set(soundFontBookmark, forKey: "audio.soundFontBookmark") }
    }
    /// 0–1.
    var builtInSoundVolume: Double {
        didSet { defaults.set(builtInSoundVolume, forKey: "audio.builtInSoundVolume") }
    }

    /// The SoundFont file, if one's chosen and can be found.
    var soundFontURL: URL? {
        guard let soundFontBookmark else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: soundFontBookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        midiDestinationID = (defaults.object(forKey: "audio.midiDestinationID") as? Int).map { MIDIUniqueID($0) }
        midiChannel = defaults.object(forKey: "audio.midiChannel") as? Int ?? 1
        previewVelocity = defaults.object(forKey: "audio.previewVelocity") as? Int ?? 90
        metronomeVolume = defaults.object(forKey: "audio.metronomeVolume") as? Double ?? 0.7
        countInBars = defaults.object(forKey: "audio.countInBars") as? Int ?? 1
        inputDeviceID = (defaults.object(forKey: "audio.inputDeviceID") as? Int).map { UInt32($0) }
        recordingOffsetMs = defaults.object(forKey: "audio.recordingOffsetMs") as? Double ?? 0
        usesBuiltInSound = defaults.object(forKey: "audio.usesBuiltInSound") as? Bool ?? true
        soundFontBookmark = defaults.data(forKey: "audio.soundFontBookmark")
        builtInSoundVolume = defaults.object(forKey: "audio.builtInSoundVolume") as? Double ?? 0.8
    }
}
