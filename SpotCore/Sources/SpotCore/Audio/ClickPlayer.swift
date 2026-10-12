//
//  ClickPlayer.swift
//  SpotCore
//

import AVFoundation

/// Plays metronome clicks at exact host times through the default audio output.
public final class ClickPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let accentClick: AVAudioPCMBuffer
    private let normalClick: AVAudioPCMBuffer

    public var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    public init() {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 44_100, channels: 1)!
        accentClick = ClickPlayer.makeClick(frequency: 1_600, format: format)
        normalClick = ClickPlayer.makeClick(frequency: 1_000, format: format)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Starts the audio engine if needed. Clicks can only be scheduled while it runs.
    public func start() throws {
        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    /// Stops sound and forgets any scheduled clicks.
    public func stop() {
        player.stop()
        engine.stop()
    }

    /// Forgets any scheduled clicks, and carries on (the engine keeps running).
    public func clear() {
        player.stop()
        if engine.isRunning {
            player.play()
        }
    }

    public func click(accent: Bool, atHostTime time: UInt64) {
        player.scheduleBuffer(accent ? accentClick : normalClick, at: AVAudioTime(hostTime: time))
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
