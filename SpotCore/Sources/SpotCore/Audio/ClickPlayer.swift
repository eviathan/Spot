//
//  ClickPlayer.swift
//  SpotCore
//

import AVFoundation
import os

/// Plays metronome clicks at exact host times, through an output of its own (see EngineOutput).
///
/// Each click is mixed in at its frame of the buffer it falls in, worked out from when that buffer will be heard,
/// so nothing is queued with the engine: clearing the clicks to come never cuts one that's sounding.
public final class ClickPlayer {
    private let engine = AVAudioEngine()
    private let output: EngineOutput?
    private let queue = ClickQueue()

    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    public init() {
        output = try? EngineOutput(engine: engine)
        let sampleRate = output?.sampleRate ?? 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let voices = ClickVoices(accent: ClickPlayer.samples(ClickPlayer.makeClick(frequency: 1_600, format: format)),
                                 normal: ClickPlayer.samples(ClickPlayer.makeClick(frequency: 1_000, format: format)),
                                 queue: queue, sampleRate: sampleRate)
        let renderTime = output?.renderTime
        let node = AVAudioSourceNode(format: format) { _, timestamp, frames, buffers in
            voices.render(at: renderTime?.hostTime ?? timestamp.pointee.mHostTime, frames: Int(frames),
                          into: UnsafeMutableAudioBufferListPointer(buffers))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Starts the sound if needed. Clicks only sound while it runs.
    public func start() throws {
        guard let output else { throw CocoaError(.featureUnsupported) }
        try output.start()
    }

    /// Stops sound and forgets any clicks to come.
    public func stop() {
        queue.push(.clear)
        output?.stop()
    }

    /// Forgets any clicks to come, and carries on (one sounding rings out).
    public func clear() {
        queue.push(.clear)
    }

    public func click(accent: Bool, atHostTime time: UInt64) {
        queue.push(.click(time: time, accent: accent))
    }

    private static func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    /// A short sine blip with a fast attack and exponential decay.
    static func makeClick(frequency: Double, format: AVAudioFormat, length: Double = 0.04) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        let attack = format.sampleRate * 0.001

        for frame in 0..<Int(frames) {
            let t = Double(frame) / format.sampleRate
            let envelope = min(1, Double(frame) / attack) * exp(-t * 90)
            samples[frame] = Float(sin(2 * .pi * frequency * t) * envelope * 0.8)
        }
        return buffer
    }
}

enum ClickCommand {
    case click(time: UInt64, accent: Bool)
    case clear
}

/// From the main thread to the audio thread, in order. A fixed ring, so the audio thread never allocates; it only
/// tries the lock, and if the main thread has it, takes them with the next buffer.
final class ClickQueue: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private static let capacity = 256
    private let slots = UnsafeMutablePointer<ClickCommand>.allocate(capacity: ClickQueue.capacity)
    private var head = 0
    private var count = 0

    deinit {
        slots.deallocate()
    }

    func push(_ command: ClickCommand) {
        lock.withLockUnchecked {
            // Full only if the audio thread isn't running: the oldest can go
            if count == Self.capacity {
                head = (head + 1) % Self.capacity
                count -= 1
            }
            slots[(head + count) % Self.capacity] = command
            count += 1
        }
    }

    /// On the audio thread: each waiting command, oldest first.
    func drain(_ body: (ClickCommand) -> Void) {
        _ = lock.withLockIfAvailableUnchecked {
            while count > 0 {
                let command = slots[head]
                head = (head + 1) % Self.capacity
                count -= 1
                body(command)
            }
        }
    }
}

/// The audio thread's side: clicks waiting for their buffer, and the ones sounding.
final class ClickVoices: @unchecked Sendable {
    private let accent: [Float]
    private let normal: [Float]
    private let queue: ClickQueue
    private let sampleRate: Double
    private var waiting: [(time: UInt64, accent: Bool)] = []
    /// Where each sounding click is up to.
    private var sounding: [(position: Int, accent: Bool)] = []
    private static let capacity = 64
    /// Clicks due this long ago still sound (late, at once); older ones are dropped.
    private static let lateLimit = 0.1

    init(accent: [Float], normal: [Float], queue: ClickQueue, sampleRate: Double) {
        self.accent = accent
        self.normal = normal
        self.queue = queue
        self.sampleRate = sampleRate
        // Room enough up front, so the audio thread never allocates
        waiting.reserveCapacity(Self.capacity)
        sounding.reserveCapacity(Self.capacity)
    }

    /// One buffer, heard from `hostTime`.
    func render(at hostTime: UInt64, frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        queue.drain { command in
            switch command {
            case .click(let time, let accent):
                if waiting.count < Self.capacity { waiting.append((time, accent)) }
            case .clear:
                waiting.removeAll(keepingCapacity: true)
            }
        }
        for buffer in buffers {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }

        // Clicks starting in this buffer: from their frame in it (a late one at once)
        var index = 0
        while index < waiting.count {
            let click = waiting[index]
            let offset = Int((HostTime.seconds(from: hostTime, to: click.time) * sampleRate).rounded())
            if offset >= frames {
                index += 1
                continue
            }
            waiting.remove(at: index)
            guard Double(-offset) / sampleRate <= Self.lateLimit, sounding.count < Self.capacity else { continue }
            // A start before this buffer is a negative position: it begins at frame 0
            sounding.append((-max(offset, 0), click.accent))
        }

        // Each sounding click, from where it's up to
        index = 0
        while index < sounding.count {
            let voice = sounding[index]
            let samples = voice.accent ? accent : normal
            let startFrame = max(0, -voice.position)
            let readFrom = max(0, voice.position)
            let count = min(frames - startFrame, samples.count - readFrom)
            if count > 0 {
                for buffer in buffers {
                    guard let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for frame in 0..<count {
                        out[startFrame + frame] += samples[readFrom + frame]
                    }
                }
            }
            let next = voice.position + frames
            if next >= samples.count {
                sounding.remove(at: index)
            } else {
                sounding[index].position = next
                index += 1
            }
        }
    }
}
