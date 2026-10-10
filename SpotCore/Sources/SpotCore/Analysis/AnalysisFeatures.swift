//
//  AnalysisFeatures.swift
//  SpotCore
//

import Accelerate

/// Magnitude spectra of fixed-size frames, via Accelerate's real FFT.
final class Spectrum {
    let size: Int
    private let log2Size: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var windowed: [Float]

    init(size: Int) {
        precondition(size.nonzeroBitCount == 1, "FFT size must be a power of two")
        self.size = size
        log2Size = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        windowed = [Float](repeating: 0, count: size)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Magnitudes of bins 0..<size/2 for the frame starting at `start` (zeros past the ends).
    func magnitudes(of samples: [Float], from start: Int) -> [Float] {
        // Copy the part of the frame that exists, then window it
        let available = (start..<(start + size)).clamped(to: 0..<samples.count)
        windowed.withUnsafeMutableBufferPointer { frame in
            frame.initialize(repeating: 0)
            if !available.isEmpty {
                samples.withUnsafeBufferPointer { source in
                    (frame.baseAddress! + (available.lowerBound - start))
                        .update(from: source.baseAddress! + available.lowerBound, count: available.count)
                }
            }
        }
        vDSP.multiply(windowed, window, result: &windowed)
        var magnitudes = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(FFT_FORWARD))
                // Bin 0 packs DC and Nyquist together; neither matters here
                split.imagp[0] = 0
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }
        return magnitudes
    }
}

/// What the analysis works from: an onset envelope (for tempo and beats) and chroma (for chords and key).
public struct AnalysisFeatures: Sendable {
    /// How strongly something new starts in each onset frame.
    public var onsets: [Float]
    /// Onsets in the bass only, to spot kick drums on downbeats.
    public var lowOnsets: [Float]
    /// Onset frames per second.
    public var onsetRate: Double
    /// Onset frame index → time of its centre in seconds.
    public var onsetFrameOffset: Double
    /// Energy in each pitch class (C = 0) for each chroma frame.
    public var chroma: [[Float]]
    public var chromaRate: Double
    public var chromaFrameOffset: Double
    /// Length of each chroma frame's window in seconds.
    public var chromaWindow: Double
    public var duration: Double

    public func onsetTime(_ frame: Int) -> Double {
        Double(frame) / onsetRate + onsetFrameOffset
    }

    public func onsetFrame(at time: Double) -> Int {
        Int(((time - onsetFrameOffset) * onsetRate).rounded())
    }

    public func chromaTime(_ frame: Int) -> Double {
        Double(frame) / chromaRate + chromaFrameOffset
    }

    /// Works out the features. Calls `progress` with 0...1 and stops if it returns false.
    public static func compute(_ audio: AudioData, progress: (Double) -> Bool = { _ in true }) -> AnalysisFeatures? {
        let (samples, sampleRate) = monoDownsampled(audio)
        guard !samples.isEmpty else { return nil }

        // Onsets: 2048-sample frames every 256 samples (~12 ms at 22 kHz)
        let onsetSize = 2048, onsetHop = 256
        let onsetSpectrum = Spectrum(size: onsetSize)
        let binHz = sampleRate / Double(onsetSize)
        let topBin = min(onsetSize / 2, Int(8_000 / binHz))
        let bassBin = max(2, Int(150 / binHz))
        let onsetFrames = samples.count / onsetHop + 1

        var onsets = [Float](repeating: 0, count: onsetFrames)
        var lowOnsets = [Float](repeating: 0, count: onsetFrames)
        var previous = [Float](repeating: 0, count: topBin - 1)
        var level = [Float](repeating: 0, count: topBin - 1)
        var rise = [Float](repeating: 0, count: topBin - 1)
        for frame in 0..<onsetFrames {
            let magnitudes = onsetSpectrum.magnitudes(of: samples, from: frame * onsetHop - onsetSize / 2)
            // Compressed level of bins 1..<topBin, and how much each rose since the last frame
            vDSP.multiply(10, magnitudes[1..<topBin], result: &level)
            vForce.log1p(level, result: &level)
            vDSP.subtract(level, previous, result: &rise)
            vDSP.clip(rise, to: 0...Float.greatestFiniteMagnitude, result: &rise)
            onsets[frame] = vDSP.sum(rise)
            lowOnsets[frame] = vDSP.sum(rise[0..<(bassBin - 1)])
            swap(&previous, &level)
            if frame % 2000 == 0 && !progress(0.6 * Double(frame) / Double(onsetFrames)) {
                return nil
            }
        }
        let onsetRate = sampleRate / Double(onsetHop)
        onsets = normalise(subtractLocalMean(onsets, window: Int(onsetRate)))
        lowOnsets = normalise(subtractLocalMean(lowOnsets, window: Int(onsetRate)))

        // Chroma: 4096-sample frames (~190 ms) every 1024 samples (~46 ms)
        let chromaSize = 4096, chromaHop = 1024
        let chromaSpectrum = Spectrum(size: chromaSize)
        let chromaBinHz = sampleRate / Double(chromaSize)
        // A 12 x bins matrix that adds each bin's energy (55 Hz to 2 kHz) to its pitch class
        let bins = chromaSize / 2
        var foldMatrix = [Float](repeating: 0, count: 12 * bins)
        for bin in 0..<bins {
            let frequency = Double(bin) * chromaBinHz
            guard frequency >= 55, frequency <= 2_000 else { continue }
            let midi = 69 + 12 * log2(frequency / 440)
            let pitchClass = ((Int(midi.rounded()) % 12) + 12) % 12
            foldMatrix[pitchClass * bins + bin] = 1
        }
        let chromaFrames = samples.count / chromaHop + 1
        var chroma: [[Float]] = []
        chroma.reserveCapacity(chromaFrames)
        var power = [Float](repeating: 0, count: bins)
        for frame in 0..<chromaFrames {
            let magnitudes = chromaSpectrum.magnitudes(of: samples, from: frame * chromaHop - chromaSize / 2)
            vDSP.square(magnitudes, result: &power)
            var classes = [Float](repeating: 0, count: 12)
            vDSP_mmul(foldMatrix, 1, power, 1, &classes, 1, 12, 1, vDSP_Length(bins))
            chroma.append(classes)
            if frame % 200 == 0 && !progress(0.6 + 0.4 * Double(frame) / Double(chromaFrames)) {
                return nil
            }
        }

        // Flux peaks when an onset is a quarter of a window past the frame centre (where a Hann window rises fastest)
        let onsetOffset = Double(onsetSize) / 4 / sampleRate
        return AnalysisFeatures(onsets: onsets, lowOnsets: lowOnsets, onsetRate: onsetRate, onsetFrameOffset: onsetOffset,
                                chroma: chroma, chromaRate: sampleRate / Double(chromaHop), chromaFrameOffset: 0,
                                chromaWindow: Double(chromaSize) / sampleRate,
                                duration: Double(samples.count) / sampleRate)
    }

    /// Mono, at roughly 22 kHz (halved from 44.1/48 kHz by averaging pairs).
    static func monoDownsampled(_ audio: AudioData) -> ([Float], Double) {
        let channels = audio.channels
        guard let first = channels.first else { return ([], audio.sampleRate) }
        var mono = first
        if channels.count > 1 {
            for channel in channels.dropFirst() {
                vDSP.add(mono, channel, result: &mono)
            }
            vDSP.multiply(1 / Float(channels.count), mono, result: &mono)
        }
        guard audio.sampleRate >= 32_000 else { return (mono, audio.sampleRate) }
        let half = mono.count / 2
        return ((0..<half).map { (mono[2 * $0] + mono[2 * $0 + 1]) / 2 }, audio.sampleRate / 2)
    }

    static func subtractLocalMean(_ values: [Float], window: Int) -> [Float] {
        guard !values.isEmpty else { return values }
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for (index, value) in values.enumerated() {
            prefix[index + 1] = prefix[index] + Double(value)
        }
        return values.indices.map { index in
            let low = max(0, index - window / 2), high = min(values.count, index + window / 2 + 1)
            let mean = (prefix[high] - prefix[low]) / Double(high - low)
            return max(0, values[index] - Float(mean))
        }
    }

    static func normalise(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return values }
        let mean = vDSP.mean(values)
        let deviation = max(0, vDSP.meanSquare(values) - mean * mean).squareRoot()
        guard deviation > 0 else { return values }
        return vDSP.divide(values, deviation)
    }
}
