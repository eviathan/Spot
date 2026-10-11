//
//  SoftSynth.swift
//  SpotCore
//

import AVFoundation
import AudioToolbox

/// Sound inside Spot, for when there's no synth on the other end of the MIDI: Apple's General MIDI synth (the
/// DLS synth, 16 channels, with macOS's own instruments), or a SoundFont (.sf2) or DLS bank in its place.
/// Takes the same MIDI messages Spot sends out, at the same times.
public final class SoftSynth {
    private let engine: AVAudioEngine
    private let instrument: AVAudioUnitMIDIInstrument
    public private(set) var soundBank: URL?
    private let scheduleBlock: AUScheduleMIDIEventBlock?
    private let pending = PendingEvents()
    private var observer: Int?

    /// GM program the channels start on: 25, a steel-string acoustic guitar (programs counted from 0).
    public static let defaultProgram = 25

    /// `engine`: a new one by default (started here); tests pass one in manual rendering mode.
    public init(engine: AVAudioEngine = AVAudioEngine(), start: Bool = true) throws {
        self.engine = engine
        let description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                    componentSubType: kAudioUnitSubType_DLSSynth,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0, componentFlagsMask: 0)
        instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        engine.attach(instrument)
        engine.connect(instrument, to: engine.mainMixerNode, format: nil)
        scheduleBlock = instrument.auAudioUnit.scheduleMIDIEventBlock

        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let pending = self.pending
        let schedule = scheduleBlock
        // Just before each buffer is rendered (on the audio thread): hand over the events due in it
        observer = instrument.auAudioUnit.token(byAddingRenderObserver: { flags, timestamp, frames, _ in
            guard flags.contains(.unitRenderAction_PreRender), !pending.isEmpty, let schedule else { return }
            // The buffer's time; offline (in tests) there's none, so now
            let stamp = timestamp.pointee
            let start = stamp.mFlags.contains(.hostTimeValid) && stamp.mHostTime > 0 ? stamp.mHostTime : HostTime.now
            let end = HostTime.adding(Double(frames) / sampleRate, to: start)
            for (time, bytes) in pending.take(before: end) {
                let offset = time > start ? HostTime.seconds(from: start, to: time) * sampleRate : 0
                bytes.withUnsafeBufferPointer { buffer in
                    schedule(AUEventSampleTimeImmediate + AUEventSampleTime(offset), 0, buffer.count, buffer.baseAddress!)
                }
            }
        })
        if start {
            try engine.start()
        }
        resetChannels()
    }

    deinit {
        if let observer { instrument.auAudioUnit.removeRenderObserver(observer) }
        engine.stop()
    }

    public var volume: Float {
        get { instrument.volume }
        set { instrument.volume = newValue }
    }

    /// Uses a SoundFont or DLS file's instruments; nil for macOS's own.
    public func loadSoundBank(_ url: URL?) throws {
        var bank: CFURL? = (url ?? SoftSynth.builtInBank) as CFURL?
        guard bank != nil else { return }
        let status = AudioUnitSetProperty(instrument.audioUnit, AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                                          kAudioUnitScope_Global, 0, &bank, UInt32(MemoryLayout<CFURL?>.size))
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't load \(url?.lastPathComponent ?? "the sound bank") (error \(status))"])
        }
        soundBank = url
        resetChannels()
    }

    /// macOS's General MIDI instruments (what the DLS synth uses unless told otherwise).
    static var builtInBank: URL? {
        let url = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Every channel on the guitar, with the bend range tabs use (±12 semitones, set by RPN 0).
    public func resetChannels() {
        for channel in UInt8(0)..<16 {
            send([0xC0 | channel, UInt8(SoftSynth.defaultProgram)])
            for (number, value) in [(101, 0), (100, 0), (6, 12), (38, 0), (101, 127), (100, 127)] {
                send([0xB0 | channel, UInt8(number), UInt8(value)])
            }
            send([0xE0 | channel, 0x00, 0x40])
        }
    }

    /// One MIDI message, sounding at `hostTime` (0 for now).
    ///
    /// The synth only takes events for the audio it's about to make (ones further ahead are dropped), so later
    /// ones wait in a queue, and each is handed over just before the buffer it falls in, at its place in it.
    public func send(_ bytes: [UInt8], atHostTime hostTime: UInt64 = 0) {
        guard !bytes.isEmpty else { return }
        if hostTime == 0 || hostTime <= HostTime.now {
            sendNow(bytes)
        } else {
            pending.add(hostTime, bytes)
        }
    }

    private func sendNow(_ bytes: [UInt8]) {
        if let scheduleBlock {
            bytes.withUnsafeBufferPointer { buffer in
                scheduleBlock(AUEventSampleTimeImmediate, 0, buffer.count, buffer.baseAddress!)
            }
        } else if bytes.count >= 2 {
            instrument.sendMIDIEvent(bytes[0], data1: bytes[1], data2: bytes.count > 2 ? bytes[2] : 0)
        }
    }

    /// Stops everything sounding, on every channel (and drops what's waiting).
    public func allNotesOff() {
        pending.removeAll()
        for channel in UInt8(0)..<16 {
            sendNow([0xB0 | channel, 123, 0])
            sendNow([0xE0 | channel, 0x00, 0x40])
        }
    }
}

/// Events waiting for their buffer, kept in time order (added from the main thread, taken on the audio thread).
private final class PendingEvents: @unchecked Sendable {
    private var events: [(time: UInt64, bytes: [UInt8])] = []
    private let lock = NSLock()

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return events.isEmpty
    }

    func add(_ time: UInt64, _ bytes: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        // Usually later than everything waiting
        let index = events.lastIndex { $0.time <= time }.map { $0 + 1 } ?? 0
        events.insert((time, bytes), at: index)
    }

    func take(before time: UInt64) -> [(time: UInt64, bytes: [UInt8])] {
        lock.lock(); defer { lock.unlock() }
        let count = events.firstIndex { $0.time >= time } ?? events.count
        let due = Array(events.prefix(count))
        events.removeFirst(count)
        return due
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        events.removeAll()
    }
}
