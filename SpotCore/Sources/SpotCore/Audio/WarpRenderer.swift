//
//  WarpRenderer.swift
//  SpotCore
//

import AVFoundation
import CStretch

/// Audio rendered onto the grid at `tempo`: frame 0 is `startBeat` (negative when the recording
/// starts before bar 1).
public struct RenderedAudio: Sendable {
    public var audio: AudioData
    public var tempo: Double
    public var startBeat: Double

    public init(audio: AudioData, tempo: Double, startBeat: Double = 0) {
        self.audio = audio
        self.tempo = tempo
        self.startBeat = startBeat
    }

    public var framesPerBeat: Double {
        audio.sampleRate * 60 / tempo
    }

    public var endBeat: Double {
        startBeat + Double(audio.frameCount) / framesPerBeat
    }

    public func frame(atBeat beat: Double) -> Int {
        Int(((beat - startBeat) * framesPerBeat).rounded())
    }

    /// A playable buffer for the beats `from..<to` (silence outside what was rendered).
    public func buffer(fromBeat from: Double, toBeat to: Double) -> AVAudioPCMBuffer? {
        let start = frame(atBeat: from), end = frame(atBeat: to)
        guard end > start else { return nil }
        return audio.buffer(frames: start..<end)
    }

    /// Replaces part of this render with a re-rendered `segment` (same tempo), crossfading at its edges
    /// so there are no clicks where the new audio joins the old. An edge with nothing to join (the edge
    /// of this render) can go without.
    public mutating func splice(_ segment: RenderedAudio, crossfade: Int = 256, fadeIn: Bool = true, fadeOut: Bool = true) {
        let offset = frame(atBeat: segment.startBeat)
        let count = segment.audio.frameCount
        for channel in audio.channels.indices where channel < segment.audio.channels.count {
            for index in 0..<count {
                let target = offset + index
                guard target >= 0, target < audio.frameCount else { continue }
                let fromEdge = min(fadeIn ? index : .max, fadeOut ? count - 1 - index : .max)
                let mix = fromEdge < crossfade ? Float(fromEdge) / Float(crossfade) : 1
                audio.channels[channel][target] = audio.channels[channel][target] * (1 - mix)
                    + segment.audio.channels[channel][index] * mix
            }
        }
    }
}

/// Lines a recording up with the beat grid by time-stretching it (without changing pitch), following a warp map.
public enum WarpRenderer {
    /// Renders `beats` beats of the grid at `tempo`, from beat 0.
    public static func render(_ source: AudioData, map: WarpMap, tempo: Double, beats: Double,
                              progress: (Double) -> Bool = { _ in true }) -> RenderedAudio? {
        render(source, map: map, tempo: tempo, from: 0, to: beats, progress: progress)
    }

    /// Renders the grid from beat `from` to beat `to` at `tempo`. Calls `progress` with 0...1 and stops
    /// early if it returns false.
    ///
    /// At the recording's own tempo (`map.tempo`), only the stretches between markers that need it are
    /// time-stretched; the rest is copied as it is, which is nearly instant.
    public static func render(_ source: AudioData, map: WarpMap, tempo: Double, from startBeat: Double, to endBeat: Double,
                              progress: (Double) -> Bool = { _ in true }) -> RenderedAudio? {
        guard abs(map.tempo - tempo) < 1e-9 else {
            return stretch(source, map: map, tempo: tempo, from: startBeat, to: endBeat, progress: progress)
        }
        guard endBeat > startBeat, !source.channels.isEmpty else { return nil }
        let sampleRate = source.sampleRate
        let framesPerBeat = sampleRate * 60 / tempo
        let outputFrames = Int((endBeat - startBeat) * framesPerBeat)
        var output = [[Float]](repeating: [Float](repeating: 0, count: outputFrames), count: source.channels.count)

        // Between each pair of markers (and beyond the outer ones) the recording either plays at its
        // own speed, just shifted, or has to be stretched
        let markers = map.markers
        let edges = [-Double.infinity] + markers.map(\.beat) + [Double.infinity]
        var stretched: [BeatRange] = []
        for (start, end) in zip(edges, edges.dropFirst()) {
            let from = max(start, startBeat), to = min(end, endBeat)
            guard to > from else { continue }
            let seconds = map.sourceTime(atBeat: to) - map.sourceTime(atBeat: from)
            let isOwnSpeed = abs(seconds - (to - from) * 60 / tempo) < 1e-6
            if !isOwnSpeed {
                // Neighbouring stretches are done in one go
                if let last = stretched.last, last.end == from {
                    stretched[stretched.count - 1] = BeatRange(last.start, to)
                } else {
                    stretched.append(BeatRange(from, to))
                }
                continue
            }
            let outStart = Int(((from - startBeat) * framesPerBeat).rounded())
            let outEnd = min(outputFrames, Int(((to - startBeat) * framesPerBeat).rounded()))
            let sourceStart = Int((map.sourceTime(atBeat: from) * sampleRate).rounded())
            // Only the part that's inside the recording
            let first = max(outStart, outStart - sourceStart)
            let last = min(outEnd, outStart + source.frameCount - sourceStart)
            guard last > first else { continue }
            for channel in output.indices {
                output[channel].withUnsafeMutableBufferPointer { destination in
                    source.channels[channel].withUnsafeBufferPointer { samples in
                        (destination.baseAddress! + first)
                            .update(from: samples.baseAddress! + sourceStart + (first - outStart), count: last - first)
                    }
                }
            }
        }

        var result = RenderedAudio(audio: AudioData(channels: output, sampleRate: sampleRate), tempo: tempo, startBeat: startBeat)
        // The stretched parts, with half a beat either side to crossfade into the copied audio
        let total = stretched.reduce(0) { $0 + $1.length }
        var done = 0.0
        for range in stretched {
            let from = max(startBeat, range.start - 0.5), to = min(endBeat, range.end + 0.5)
            guard let segment = stretch(source, map: map, tempo: tempo, from: from, to: to, progress: { fraction in
                progress((done + fraction * range.length) / max(total, 1e-9))
            }) else { return nil }
            result.splice(segment, fadeIn: from > startBeat, fadeOut: to < endBeat)
            done += range.length
        }
        return result
    }

    /// Time-stretches the whole of `from..<to`.
    private static func stretch(_ source: AudioData, map: WarpMap, tempo: Double, from startBeat: Double, to endBeat: Double,
                                progress: (Double) -> Bool) -> RenderedAudio? {
        let beats = endBeat - startBeat
        let channelCount = source.channels.count
        let sampleRate = source.sampleRate
        guard channelCount > 0, beats > 0, let stretch = cstretch_create(Int32(channelCount), Float(sampleRate)) else {
            return nil
        }
        defer { cstretch_destroy(stretch) }

        let outputFrames = Int(beats * 60 / tempo * sampleRate)
        let inputLatency = Int(cstretch_input_latency(stretch))
        let outputLatency = Int(cstretch_output_latency(stretch))
        let blockSize = 1024

        /// Which input sample should be at the processing point when output frame `frame` is produced.
        func inputPosition(forOutputFrame frame: Int) -> Int {
            let beat = startBeat + Double(frame) / sampleRate * tempo / 60
            return Int((map.sourceTime(atBeat: beat) * sampleRate).rounded())
        }

        var output = [[Float]](repeating: [Float](repeating: 0, count: outputFrames), count: channelCount)

        // Per-channel scratch buffers handed to the C API; input grows if a block needs more
        var inputCapacity = max(inputLatency, blockSize * 4)
        var inputs = (0..<channelCount).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: inputCapacity) }
        let outputs = (0..<channelCount).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: blockSize) }
        defer {
            inputs.forEach { $0.deallocate() }
            outputs.forEach { $0.deallocate() }
        }

        /// Copies source frames (zeros outside the recording) into the input buffers.
        func fillInput(from start: Int, count: Int) {
            if count > inputCapacity {
                inputs.forEach { $0.deallocate() }
                inputCapacity = count
                inputs = (0..<channelCount).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: inputCapacity) }
            }
            let available = (start..<(start + count)).clamped(to: 0..<source.frameCount)
            for channel in 0..<channelCount {
                inputs[channel].initialize(repeating: 0, count: count)
                if !available.isEmpty {
                    source.channels[channel].withUnsafeBufferPointer { samples in
                        (inputs[channel] + (available.lowerBound - start))
                            .update(from: samples.baseAddress! + available.lowerBound, count: available.count)
                    }
                }
            }
        }

        func inputPointers() -> [UnsafePointer<Float>?] {
            inputs.map { UnsafePointer($0) }
        }

        // Output trails the processing point by `outputLatency`, so render that much pre-roll and drop it,
        // and keep the processing point that far ahead of the frame being written
        var inputCursor = inputPosition(forOutputFrame: 0)
        fillInput(from: inputCursor, count: inputLatency)
        inputPointers().withUnsafeBufferPointer {
            cstretch_seek(stretch, $0.baseAddress, Int32(inputLatency), 1)
        }
        inputCursor += inputLatency

        let outputPointers: [UnsafeMutablePointer<Float>?] = outputs
        var frame = -outputLatency
        while frame < outputFrames {
            let count = min(blockSize, outputFrames - frame)
            // Feed input up to where the processing point should be at the end of this block
            let target = inputPosition(forOutputFrame: frame + count + outputLatency) + inputLatency
            let inputCount = max(0, target - inputCursor)
            fillInput(from: inputCursor, count: inputCount)
            inputCursor += inputCount

            inputPointers().withUnsafeBufferPointer { inputs in
                outputPointers.withUnsafeBufferPointer { outputs in
                    cstretch_process(stretch, inputs.baseAddress, Int32(inputCount), outputs.baseAddress, Int32(count))
                }
            }

            let skip = max(0, -frame)
            if skip < count {
                for channel in 0..<channelCount {
                    output[channel].withUnsafeMutableBufferPointer { destination in
                        (destination.baseAddress! + frame + skip).update(from: outputs[channel] + skip, count: count - skip)
                    }
                }
            }
            frame += count

            if !progress(Double(max(frame, 0)) / Double(max(outputFrames, 1))) {
                return nil
            }
        }

        return RenderedAudio(audio: AudioData(channels: output, sampleRate: sampleRate), tempo: tempo, startBeat: startBeat)
    }
}
