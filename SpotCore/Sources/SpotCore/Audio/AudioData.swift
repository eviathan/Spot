//
//  AudioData.swift
//  SpotCore
//

import AVFoundation
import CryptoKit

/// Decoded audio as one array of samples per channel.
public struct AudioData: Sendable {
    public var channels: [[Float]]
    public var sampleRate: Double

    public init(channels: [[Float]], sampleRate: Double) {
        self.channels = channels
        self.sampleRate = sampleRate
    }

    public var frameCount: Int {
        channels.first?.count ?? 0
    }

    public var duration: Double {
        Double(frameCount) / sampleRate
    }

    /// Reads a whole audio file (any format AVFoundation can decode).
    public static func load(_ url: URL) throws -> AudioData {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadUnknown)
        }
        try file.read(into: buffer)

        let frames = Int(buffer.frameLength)
        let channels = (0..<Int(format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: frames))
        }
        return AudioData(channels: channels, sampleRate: format.sampleRate)
    }

    /// A buffer AVAudioEngine can play, covering `range` of frames (zeros outside the audio).
    public func buffer(frames range: Range<Int>) -> AVAudioPCMBuffer? {
        guard range.count > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels.count)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(range.count)
        let available = range.clamped(to: 0..<frameCount)

        for (index, samples) in channels.enumerated() {
            let destination = buffer.floatChannelData![index]
            destination.initialize(repeating: 0, count: range.count)
            if !available.isEmpty {
                samples.withUnsafeBufferPointer { source in
                    (destination + (available.lowerBound - range.lowerBound))
                        .update(from: source.baseAddress! + available.lowerBound, count: available.count)
                }
            }
        }
        return buffer
    }
}

public enum AudioFingerprint {
    /// Hashes the file's size and its first and last megabyte: quick, and different for different recordings.
    public static func of(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        var hasher = SHA256()
        hasher.update(data: withUnsafeBytes(of: size.littleEndian) { Data($0) })

        let chunk = 1 << 20
        try handle.seek(toOffset: 0)
        hasher.update(data: try handle.read(upToCount: chunk) ?? Data())
        if size > UInt64(chunk) {
            try handle.seek(toOffset: size - UInt64(chunk))
            hasher.update(data: try handle.read(upToCount: chunk) ?? Data())
        }
        return hasher.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// Loudness overview for drawing a waveform: the min and max of each block of samples (channels mixed).
public struct WaveformPeaks: Sendable {
    public let samplesPerBlock: Int
    public let sampleRate: Double
    public let minimums: [Float]
    public let maximums: [Float]

    public init(_ audio: AudioData, samplesPerBlock: Int = 256) {
        self.samplesPerBlock = samplesPerBlock
        self.sampleRate = audio.sampleRate
        let blocks = (audio.frameCount + samplesPerBlock - 1) / samplesPerBlock
        var minimums = [Float](repeating: 0, count: blocks)
        var maximums = [Float](repeating: 0, count: blocks)
        let scale = 1 / Float(max(audio.channels.count, 1))

        for block in 0..<blocks {
            let start = block * samplesPerBlock
            let end = min(start + samplesPerBlock, audio.frameCount)
            var low: Float = 0, high: Float = 0
            for frame in start..<end {
                var sample: Float = 0
                for channel in audio.channels {
                    sample += channel[frame]
                }
                sample *= scale
                low = min(low, sample)
                high = max(high, sample)
            }
            minimums[block] = low
            maximums[block] = high
        }
        self.minimums = minimums
        self.maximums = maximums
    }

    /// The quietest and loudest sample between two times in seconds.
    public func range(from start: Double, to end: Double) -> (min: Float, max: Float) {
        let first = max(0, Int(start * sampleRate) / samplesPerBlock)
        let last = min(maximums.count - 1, Int(end * sampleRate) / samplesPerBlock)
        guard first <= last else { return (0, 0) }
        var low: Float = 0, high: Float = 0
        for block in first...last {
            low = min(low, minimums[block])
            high = max(high, maximums[block])
        }
        return (low, high)
    }
}
