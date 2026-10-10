//
//  TrackPlayer.swift
//  SpotCore
//

import AVFoundation

/// Plays rendered audio in back-to-back slices, starting at an exact host time.
/// A time-pitch unit slows it down for practice without changing the pitch.
public final class TrackPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var format: AVAudioFormat?

    /// 1 is normal speed, 0.5 half speed.
    public var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = min(max(newValue, 0.25), 2) }
    }

    /// 0...1 (and above for boost).
    public var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public init() {
        engine.attach(player)
        engine.attach(timePitch)
    }

    /// Stops anything playing and starts `firstSlice` at `hostTime`. Later slices are queued straight after it.
    public func start(_ firstSlice: AVAudioPCMBuffer, atHostTime hostTime: UInt64) throws {
        player.stop()
        if format != firstSlice.format {
            engine.stop()
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(timePitch)
            engine.connect(player, to: timePitch, format: firstSlice.format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: firstSlice.format)
            format = firstSlice.format
        }
        if !engine.isRunning {
            try engine.start()
        }
        player.scheduleBuffer(firstSlice)
        player.play(at: AVAudioTime(hostTime: hostTime))
    }

    /// Queues a slice to play as soon as the previous one ends.
    public func append(_ slice: AVAudioPCMBuffer) {
        player.scheduleBuffer(slice)
    }

    public func stop() {
        player.stop()
    }
}
