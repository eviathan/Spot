//
//  AudioData.swift
//  SpotCore
//

import Accelerate
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
    /// One level of detail: the lowest and highest sample in each block.
    public struct Level: Sendable {
        public let samplesPerBlock: Int
        public let minimums: [Float]
        public let maximums: [Float]
    }

    public let sampleRate: Double
    /// Finest first, each `levelFactor` times coarser, down to a few hundred blocks: whatever the zoom, a column
    /// of the waveform looks at only a handful of blocks.
    public let levels: [Level]
    static let levelFactor = 4

    /// The finest level's.
    public var samplesPerBlock: Int { levels[0].samplesPerBlock }
    public var minimums: [Float] { levels[0].minimums }
    public var maximums: [Float] { levels[0].maximums }

    public init(_ audio: AudioData, samplesPerBlock: Int = 8) {
        self.sampleRate = audio.sampleRate
        let frames = audio.frameCount
        let blockSize = max(1, samplesPerBlock)
        let blocks = (frames + blockSize - 1) / blockSize

        // The channels mixed, padded with silence to whole blocks (all with Accelerate: a plain loop over every
        // sample takes seconds in a debug build)
        var mixed = audio.channels.first.map { Array($0.prefix(frames)) } ?? []
        for channel in audio.channels.dropFirst() {
            vDSP_vadd(mixed, 1, channel, 1, &mixed, 1, vDSP_Length(frames))
        }
        var scale = 1 / Float(max(audio.channels.count, 1))
        vDSP_vsmul(mixed, 1, &scale, &mixed, 1, vDSP_Length(mixed.count))
        mixed += [Float](repeating: 0, count: blocks * blockSize - mixed.count)

        // Silence counts: the lowest is at most 0 and the highest at least 0
        var finest = Level(samplesPerBlock: blockSize,
                           minimums: WaveformPeaks.reduce(mixed, by: blockSize, vDSP_vmin, start: [Float](repeating: 0, count: blocks)),
                           maximums: WaveformPeaks.reduce(mixed, by: blockSize, vDSP_vmax, start: [Float](repeating: 0, count: blocks)))
        if blocks == 0 { finest = Level(samplesPerBlock: blockSize, minimums: [], maximums: []) }
        var levels = [finest]
        while let last = levels.last, last.minimums.count > 512 {
            let factor = WaveformPeaks.levelFactor
            let count = (last.minimums.count + factor - 1) / factor
            let pad = [Float](repeating: 0, count: count * factor - last.minimums.count)
            levels.append(Level(samplesPerBlock: last.samplesPerBlock * factor,
                                minimums: WaveformPeaks.reduce(last.minimums + pad, by: factor, vDSP_vmin, start: nil),
                                maximums: WaveformPeaks.reduce(last.maximums + pad, by: factor, vDSP_vmax, start: nil)))
        }
        self.levels = levels
    }

    /// Every `factor` values combined into one (with vDSP_vmin or vDSP_vmax), a whole stride at a time.
    private static func reduce(_ values: [Float], by factor: Int,
                               _ combine: (UnsafePointer<Float>, vDSP_Stride, UnsafePointer<Float>, vDSP_Stride,
                                           UnsafeMutablePointer<Float>, vDSP_Stride, vDSP_Length) -> Void,
                               start: [Float]?) -> [Float] {
        let count = values.count / factor
        guard count > 0 else { return [] }
        var result = start ?? Array(values[0...].striding(factor, count))
        values.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            result.withUnsafeMutableBufferPointer { out in
                for offset in (start == nil ? 1 : 0)..<factor {
                    combine(base + offset, vDSP_Stride(factor), UnsafePointer(out.baseAddress!), 1, out.baseAddress!, 1, vDSP_Length(count))
                }
            }
        }
        return result
    }

    /// The quietest and loudest sample between two times in seconds, from the coarsest level that still has a
    /// few blocks in that time.
    public func range(from start: Double, to end: Double) -> (min: Float, max: Float) {
        let span = (end - start) * sampleRate
        // (Worked out, rather than searched for: this runs for every column of the waveform on every redraw)
        let steps = span > Double(samplesPerBlock * 2)
            ? Int(log(span / Double(samplesPerBlock * 2)) / log(Double(WaveformPeaks.levelFactor)) + 1e-9) : 0
        let level = levels[min(max(steps, 0), levels.count - 1)]
        let first = max(0, Int(start * sampleRate) / level.samplesPerBlock)
        let last = min(level.maximums.count - 1, Int(end * sampleRate) / level.samplesPerBlock)
        guard first <= last else { return (0, 0) }
        var low: Float = 0, high: Float = 0
        level.minimums.withUnsafeBufferPointer { vDSP_minv($0.baseAddress! + first, 1, &low, vDSP_Length(last - first + 1)) }
        level.maximums.withUnsafeBufferPointer { vDSP_maxv($0.baseAddress! + first, 1, &high, vDSP_Length(last - first + 1)) }
        return (min(low, 0), max(high, 0))
    }
}

private extension ArraySlice where Element == Float {
    /// Every `step`th value from the start, `count` of them.
    func striding(_ step: Int, _ count: Int) -> [Float] {
        (0..<count).map { self[startIndex + $0 * step] }
    }
}
