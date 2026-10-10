//
//  BeatTracker.swift
//  SpotCore
//

import Foundation
import Accelerate

public struct TempoCandidate: Hashable, Sendable {
    public var bpm: Double
    /// Relative strength, 0...1 (the best candidate is 1).
    public var confidence: Double
}

public enum BeatTracker {
    /// Likely tempos, best first. Half and double the best are always included (if in range),
    /// since that's the commonest mistake and is easy to fix by choosing another candidate.
    public static func tempoCandidates(_ features: AnalysisFeatures, range: ClosedRange<Double> = 50...220) -> [TempoCandidate] {
        let envelope = features.onsets
        let rate = features.onsetRate
        let minLag = max(1, Int(60 * rate / range.upperBound))
        let maxLag = min(envelope.count - 1, Int(60 * rate / range.lowerBound))
        guard maxLag > minLag else { return [] }

        // Autocorrelation, weighted towards ~120 bpm (a log-normal prior an octave wide)
        var scores = [Double](repeating: 0, count: maxLag + 2)
        for lag in minLag...maxLag {
            let sum = Double(vDSP.dot(envelope[0..<(envelope.count - lag)], envelope[lag...]))
            let bpm = 60 * rate / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / 120), 2))
            scores[lag] = sum / Double(envelope.count - lag) * prior
        }

        // Peaks, refined to fractional lags
        var peaks: [(bpm: Double, score: Double)] = []
        for lag in (minLag + 1)..<maxLag where scores[lag] > scores[lag - 1] && scores[lag] >= scores[lag + 1] {
            let (a, b, c) = (scores[lag - 1], scores[lag], scores[lag + 1])
            let shift = (a - 2 * b + c) == 0 ? 0 : 0.5 * (a - c) / (a - 2 * b + c)
            peaks.append((60 * rate / (Double(lag) + shift), b))
        }
        peaks.sort { $0.score > $1.score }
        guard let best = peaks.first, best.score > 0 else { return [] }

        var candidates = [TempoCandidate(bpm: best.bpm, confidence: 1)]
        for factor in [0.5, 2.0] where range.contains(best.bpm * factor) {
            let related = peaks.first { abs($0.bpm / (best.bpm * factor) - 1) < 0.04 }
            candidates.append(TempoCandidate(bpm: related?.bpm ?? best.bpm * factor, confidence: (related?.score ?? 0) / best.score))
        }
        for peak in peaks.dropFirst() where !candidates.contains(where: { abs($0.bpm / peak.bpm - 1) < 0.04 }) && candidates.count < 5 {
            candidates.append(TempoCandidate(bpm: peak.bpm, confidence: peak.score / best.score))
        }
        return candidates
    }

    /// Beat times in seconds following `bpm`, allowed to drift with the music (Ellis 2007 dynamic programming).
    public static func beats(_ features: AnalysisFeatures, bpm: Double, tightness: Double = 100) -> [Double] {
        let envelope = features.onsets
        let period = 60 * features.onsetRate / bpm
        guard envelope.count > Int(2 * period), period > 1 else { return [] }

        // Smooth the envelope slightly so near misses still count
        let radius = max(1, Int(period / 16))
        let local: [Double] = envelope.indices.map { index in
            var sum: Double = 0, weightSum: Double = 0
            for offset in -radius...radius where envelope.indices.contains(index + offset) {
                let weight = exp(-0.5 * pow(Double(offset) / (Double(radius) / 2), 2))
                sum += weight * Double(envelope[index + offset])
                weightSum += weight
            }
            return sum / weightSum
        }

        var cumulative = local
        var backlink = [Int](repeating: -1, count: envelope.count)
        let earliest = Int((2 * period).rounded()), latest = max(1, Int((period / 2).rounded()))
        // Penalty for each gap between beats, by its length in frames
        let costs = (0...earliest).map { gap in gap == 0 ? -Double.infinity : -tightness * pow(log(Double(gap) / period), 2) }
        for index in envelope.indices {
            var best = -Double.infinity, bestPrevious = -1
            let low = max(0, index - earliest), high = index - latest
            guard high >= low else { continue }
            for previous in low...high {
                let score = cumulative[previous] + costs[index - previous]
                if score > best {
                    best = score
                    bestPrevious = previous
                }
            }
            // Starting a fresh run of beats costs nothing, so the first beat isn't pulled towards the start
            if bestPrevious >= 0 && best > 0 {
                cumulative[index] = local[index] + best
                backlink[index] = bestPrevious
            }
        }

        // End on the strongest beat in the last period, then walk back
        let tailStart = max(0, envelope.count - Int(period))
        var index = (tailStart..<envelope.count).max { cumulative[$0] < cumulative[$1] } ?? envelope.count - 1
        var frames: [Int] = []
        while index >= 0 {
            frames.append(index)
            index = backlink[index]
        }
        return frames.reversed().map(features.onsetTime)
    }

    /// Which beat starts bar 1 (an index into `beats`, less than `beatsPerBar`): the phase where
    /// bass hits and chord changes land most often.
    public static func downbeatPhase(_ features: AnalysisFeatures, beats: [Double], beatsPerBar: Int,
                                     chroma beatChroma: [[Float]]) -> Int {
        guard beatsPerBar > 1, beats.count >= beatsPerBar * 2 else { return 0 }
        let bass = beats.map { time -> Double in
            let frame = features.onsetFrame(at: time)
            let window = max(0, frame - 2)...min(features.lowOnsets.count - 1, max(0, frame + 2))
            return Double(window.map { features.lowOnsets[$0] }.max() ?? 0)
        }
        let change = beats.indices.map { index -> Double in
            guard index > 0, index < beatChroma.count else { return 0 }
            return 1 - cosine(beatChroma[index - 1], beatChroma[index])
        }

        let scores = (0..<beatsPerBar).map { phase -> Double in
            let indices = stride(from: phase, to: beats.count, by: beatsPerBar)
            let count = Double(indices.underestimatedCount)
            return indices.reduce(0) { $0 + bass[$1] + 2 * change[$1] } / max(count, 1)
        }
        return scores.indices.max { scores[$0] < scores[$1] } ?? 0
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        var dot: Double = 0, normA: Double = 0, normB: Double = 0
        for (x, y) in zip(a, b) {
            dot += Double(x * y)
            normA += Double(x * x)
            normB += Double(y * y)
        }
        return normA > 0 && normB > 0 ? dot / (normA.squareRoot() * normB.squareRoot()) : 0
    }
}
