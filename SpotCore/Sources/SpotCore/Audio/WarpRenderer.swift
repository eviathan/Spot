//
//  WarpRenderer.swift
//  SpotCore
//

import AVFoundation
import CStretch

/// Audio rendered onto the grid: frame 0 is beat 0 at `tempo`.
public struct RenderedAudio: Sendable {
    public var audio: AudioData
    public var tempo: Double

    public var framesPerBeat: Double {
        audio.sampleRate * 60 / tempo
    }

    /// A playable buffer for the beats `from..<to`.
    public func buffer(fromBeat from: Double, toBeat to: Double) -> AVAudioPCMBuffer? {
        let start = Int((from * framesPerBeat).rounded())
        let end = Int((to * framesPerBeat).rounded())
        return audio.buffer(frames: start..<end)
    }
}

/// Lines a recording up with the beat grid by time-stretching it (without changing pitch), following a warp map.
public enum WarpRenderer {
    /// Renders `beats` beats of the grid at `tempo`. Calls `progress` with 0...1 and stops early if it returns false.
    public static func render(_ source: AudioData, map: WarpMap, tempo: Double, beats: Double,
                              progress: (Double) -> Bool = { _ in true }) -> RenderedAudio? {
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
            let beat = Double(frame) / sampleRate * tempo / 60
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

        return RenderedAudio(audio: AudioData(channels: output, sampleRate: sampleRate), tempo: tempo)
    }
}
