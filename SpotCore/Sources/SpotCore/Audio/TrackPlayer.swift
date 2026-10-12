//
//  TrackPlayer.swift
//  SpotCore
//

import AVFoundation
import os

/// Plays rendered audio along with the transport, the way a DAW does: the audio engine pulls it a buffer at a
/// time, rather than it being queued up ahead. So starting, going back at a loop's end and swapping in a new
/// render are all taken up within a buffer, and nothing ever has to be thrown away and queued again. Every join
/// is crossfaded over a few milliseconds, so none of them clicks.
/// A time-pitch unit slows it down for practice without changing the pitch (it's never stopped, so it never
/// has to settle again).
public final class TrackPlayer {
    /// The crossfade at every join, and the fades in and out at a start and stop (seconds).
    static let fadeLength = 0.005

    private let engine = AVAudioEngine()
    private let timePitch = AVAudioUnitTimePitch()
    private var node: AVAudioSourceNode?
    private var format: AVAudioFormat?
    private let commands = CommandQueue()
    private let renderer: Renderer
    /// The recording last handed to the audio thread, and earlier ones kept a while after they were replaced:
    /// the audio thread should never be the one to free a recording (it would hold up the sound).
    private var current: Source?
    private var retired: [(source: Source, until: UInt64)] = []

    /// 1 is normal speed, 0.5 half speed (what the time-pitch unit allows: 1/32 to 32).
    public var rate: Float {
        get { timePitch.rate }
        set {
            timePitch.rate = min(max(newValue, 1 / 32), 32)
            commands.setRate(Double(timePitch.rate))
        }
    }

    /// 0...1 (and above for boost). Changes are smoothed over a buffer.
    public var volume: Float = 1 {
        didSet { commands.setGain(volume) }
    }

    public init() {
        renderer = Renderer(commands: commands)
        engine.attach(timePitch)
    }

    /// Plays `audio` from `beat`, starting at `hostTime` (if that's already gone, from as far on as it should be).
    /// Anything playing fades out.
    public func start(_ audio: RenderedAudio, atBeat beat: Double, hostTime: UInt64) throws {
        let source = try prepare(audio)
        commands.push(.start(source, beat: beat, hostTime: hostTime))
    }

    /// Swaps in a new render while playing, carrying on at the same beat (crossfaded from the old one).
    public func replace(with audio: RenderedAudio) throws {
        let source = try prepare(audio)
        commands.push(.replace(source))
    }

    /// When playback reaches `beat`, carries on from `target` (a loop going round). If it's already past `beat`
    /// (asked too late), it goes now, as far past `target`.
    public func jump(at beat: Double, to target: Double) {
        commands.push(.jump(at: beat, to: target))
    }

    /// Fades out. The engine keeps running, so the next start is straight away.
    public func stop() {
        commands.push(.stop)
        if let current {
            retire(current)
            self.current = nil
        }
    }

    // MARK: - Setting up

    private func prepare(_ audio: RenderedAudio) throws -> Source {
        let source = Source(audio)
        let channels = AVAudioChannelCount(min(max(audio.audio.channels.count, 1), 2))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: audio.audio.sampleRate, channels: channels) else {
            throw CocoaError(.featureUnsupported)
        }
        if format != self.format {
            connect(format)
        }
        if !engine.isRunning {
            try engine.start()
        }
        if let current {
            retire(current)
        }
        current = source
        return source
    }

    /// A source node for recordings in `format`. The renderer carries on across it, so what's playing keeps going.
    private func connect(_ format: AVAudioFormat) {
        engine.stop()
        if let node {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        engine.disconnectNodeOutput(timePitch)
        let renderer = renderer
        let sampleRate = format.sampleRate
        let node = AVAudioSourceNode(format: format) { _, timestamp, frameCount, buffers in
            renderer.render(timestamp.pointee, frames: Int(frameCount), sampleRate: sampleRate,
                            into: UnsafeMutableAudioBufferListPointer(buffers))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        self.node = node
        self.format = format
    }

    /// Keeps `source` for a couple of seconds, long after the audio thread has let go of it.
    private func retire(_ source: Source) {
        let now = HostTime.now
        retired.removeAll { $0.until < now }
        retired.append((source, HostTime.adding(2, to: now)))
    }
}

/// A recording ready for the audio thread.
final class Source {
    let audio: RenderedAudio
    let channels: [[Float]]

    init(_ audio: RenderedAudio) {
        self.audio = audio
        channels = audio.audio.channels
    }

    func frame(atBeat beat: Double) -> Int {
        audio.frame(atBeat: beat)
    }

    func beat(atFrame frame: Int) -> Double {
        audio.startBeat + Double(frame) / audio.framesPerBeat
    }
}

enum Command {
    case start(Source, beat: Double, hostTime: UInt64)
    case replace(Source)
    case jump(at: Double, to: Double)
    case stop
}

/// From the main thread to the audio thread: commands in order, and the volume and rate. A fixed ring, so the
/// audio thread never allocates; it only tries the lock, and if the main thread has it, waits for the next buffer.
final class CommandQueue {
    private let lock = OSAllocatedUnfairLock()
    private static let capacity = 64
    private let slots: UnsafeMutablePointer<Command?>
    private var head = 0
    private var count = 0
    private var gain: Float = 1
    private var rate = 1.0

    init() {
        slots = .allocate(capacity: Self.capacity)
        slots.initialize(repeating: nil, count: Self.capacity)
    }

    deinit {
        slots.deinitialize(count: Self.capacity)
        slots.deallocate()
    }

    func push(_ command: Command) {
        lock.withLockUnchecked {
            // Full only if the audio thread isn't running: the oldest can go
            if count == Self.capacity {
                slots[head] = nil
                head = (head + 1) % Self.capacity
                count -= 1
            }
            slots[(head + count) % Self.capacity] = command
            count += 1
        }
    }

    func setGain(_ value: Float) {
        lock.withLockUnchecked { gain = value }
    }

    func setRate(_ value: Double) {
        lock.withLockUnchecked { rate = value }
    }

    /// On the audio thread: hands over each waiting command, then the volume and rate. Nil if the lock was busy.
    func drain(_ body: (Command) -> Void) -> (gain: Float, rate: Double)? {
        lock.withLockIfAvailableUnchecked {
            while count > 0 {
                let command = slots[head]
                slots[head] = nil
                head = (head + 1) % Self.capacity
                count -= 1
                if let command { body(command) }
            }
            return (gain, rate)
        }
    }
}

/// Everything the audio thread keeps: where it's up to in the recording, and the voices fading out of joins.
final class Renderer {
    struct Voice {
        let source: Source
        var frame: Int
        var gain: Float
        /// Each frame: up while fading in, down while fading out.
        var step: Float
    }

    private let commands: CommandQueue
    private var main: Voice?
    /// Voices fading out (a few at most: each lasts `fadeLength`).
    private var fading: [Voice] = []
    private var pendingStart: (source: Source, beat: Double, hostTime: UInt64)?
    private var jumps: [(at: Double, to: Double)] = []
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var rate = 1.0
    private static let maxFading = 8
    private static let maxJumps = 8

    init(commands: CommandQueue) {
        self.commands = commands
        // Room enough up front, so the audio thread never allocates
        fading.reserveCapacity(Self.maxFading + 1)
        jumps.reserveCapacity(Self.maxJumps + 1)
    }

    func render(_ time: AudioTimeStamp, frames: Int, sampleRate: Double, into buffers: UnsafeMutableAudioBufferListPointer) {
        let fade = max(1, Int(sampleRate * TrackPlayer.fadeLength))
        if let values = commands.drain({ apply($0, fade: fade) }) {
            targetGain = values.gain
            rate = values.rate
        }
        for buffer in buffers {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        // What's fading out carries on fading
        var index = 0
        while index < fading.count {
            mix(&fading[index], into: buffers, at: 0, count: frames)
            if fading[index].gain <= 0 { fading.remove(at: index) } else { index += 1 }
        }

        // Starting: from its frame in this buffer (this buffer's time is when its first frame is heard; frames here
        // are the recording's, which go by `rate` times as fast)
        var from = 0
        if let start = pendingStart {
            let early = time.mFlags.contains(.hostTimeValid) ? HostTime.seconds(from: time.mHostTime, to: start.hostTime) : 0
            let offset = Int((early * sampleRate * rate).rounded())
            if offset < frames {
                main = Voice(source: start.source, frame: start.source.frame(atBeat: start.beat) + max(0, -offset),
                             gain: 0, step: 1 / Float(fade))
                from = max(0, offset)
                pendingStart = nil
            } else {
                from = frames
            }
        }

        // Playing on, going back wherever a jump falls
        if var voice = main {
            var at = from
            while at < frames {
                guard let jump = jumps.first else {
                    mix(&voice, into: buffers, at: at, count: frames - at)
                    break
                }
                let jumpFrame = voice.source.frame(atBeat: jump.at)
                if jumpFrame <= voice.frame {
                    // Due now (or overdue): the old place fades out as the new one fades in
                    jumps.removeFirst()
                    fadeOut(voice, fade: fade, into: buffers, at: at, frames: frames)
                    voice = Voice(source: voice.source, frame: voice.source.frame(atBeat: jump.to) + (voice.frame - jumpFrame),
                                  gain: 0, step: 1 / Float(fade))
                    continue
                }
                let count = min(frames - at, jumpFrame - voice.frame)
                mix(&voice, into: buffers, at: at, count: count)
                at += count
            }
            main = voice
        }

        // The volume, smoothed across the buffer
        if gain != 1 || targetGain != 1 {
            let step = (targetGain - gain) / Float(max(frames, 1))
            for buffer in buffers {
                guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                var level = gain
                for frame in 0..<frames {
                    out[frame] *= level
                    level += step
                }
            }
            gain = targetGain
        }
    }

    private func apply(_ command: Command, fade: Int) {
        switch command {
        case .start(let source, let beat, let hostTime):
            // Somewhere new: what's playing fades out now (its jumps were for where it was going)
            if let voice = main { addFading(voice, fade: fade) }
            main = nil
            pendingStart = (source, beat, hostTime)
            jumps.removeAll(keepingCapacity: true)
        case .replace(let source):
            if let start = pendingStart {
                pendingStart = (source, start.beat, start.hostTime)
            }
            if let voice = main {
                addFading(voice, fade: fade)
                main = Voice(source: source, frame: source.frame(atBeat: voice.source.beat(atFrame: voice.frame)),
                             gain: 0, step: 1 / Float(fade))
            }
        case .jump(let at, let to):
            if jumps.count == Self.maxJumps { jumps.removeFirst() }
            jumps.append((at, to))
        case .stop:
            if let voice = main { addFading(voice, fade: fade) }
            main = nil
            pendingStart = nil
            jumps.removeAll(keepingCapacity: true)
        }
    }

    /// Fades `voice` out from `at` in this buffer, then carries on fading it in the next ones.
    private func fadeOut(_ voice: Voice, fade: Int, into buffers: UnsafeMutableAudioBufferListPointer, at: Int, frames: Int) {
        var voice = voice
        voice.step = -1 / Float(fade)
        mix(&voice, into: buffers, at: at, count: frames - at)
        if voice.gain > 0 { addFading(voice, fade: nil) }
    }

    /// Adds a voice to fade out from the start of the next buffer mixed (`fade` sets it fading; nil if it already is).
    private func addFading(_ voice: Voice, fade: Int?) {
        var voice = voice
        if let fade { voice.step = -1 / Float(fade) }
        if fading.count == Self.maxFading { fading.removeFirst() }
        fading.append(voice)
    }

    /// Adds `count` frames of `voice` to the buffers from `offset`, ramping its gain, and moves it on.
    private func mix(_ voice: inout Voice, into buffers: UnsafeMutableAudioBufferListPointer, at offset: Int, count: Int) {
        guard count > 0 else { return }
        let channels = voice.source.channels
        if !channels.isEmpty {
            for (index, buffer) in buffers.enumerated() {
                guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                // A mono recording plays in both ears
                channels[min(index, channels.count - 1)].withUnsafeBufferPointer { samples in
                    var gain = voice.gain
                    var frame = voice.frame
                    for position in offset..<(offset + count) {
                        if frame >= 0, frame < samples.count {
                            out[position] += samples[frame] * gain
                        }
                        frame += 1
                        gain = min(1, max(0, gain + voice.step))
                    }
                }
            }
        }
        voice.frame += count
        voice.gain = min(1, max(0, voice.gain + voice.step * Float(count)))
    }
}
