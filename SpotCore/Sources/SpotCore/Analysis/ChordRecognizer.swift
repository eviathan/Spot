//
//  ChordRecognizer.swift
//  SpotCore
//

import Foundation
import Accelerate

/// A chord heard over a run of beats.
public struct DetectedChord: Hashable, Sendable {
    public enum Quality: String, CaseIterable, Sendable {
        case major, minor, dominant7, major7, minor7, diminished

        /// Pitch classes above the root and how much each counts.
        var template: [(Int, Float)] {
            switch self {
            case .major: return [(0, 1), (4, 1), (7, 1)]
            case .minor: return [(0, 1), (3, 1), (7, 1)]
            case .dominant7: return [(0, 1), (4, 1), (7, 1), (10, 0.8)]
            case .major7: return [(0, 1), (4, 1), (7, 1), (11, 0.8)]
            case .minor7: return [(0, 1), (3, 1), (7, 1), (10, 0.8)]
            case .diminished: return [(0, 1), (3, 1), (6, 1)]
            }
        }

        /// The library symbol for this quality.
        public var symbol: String {
            switch self {
            case .major: return ""
            case .minor: return "m"
            case .dominant7: return "7"
            case .major7: return "maj7"
            case .minor7: return "m7"
            case .diminished: return "dim"
            }
        }
    }

    /// Index of the first beat (into the beat list the chords were found for), and one past the last.
    public var beats: Range<Int>
    /// nil when nothing chord-like was heard (silence, drums only).
    public var root: PitchClass?
    public var quality: Quality

    public func symbol(in key: Key?) -> String? {
        guard let root else { return nil }
        let name = key?.spell(root) ?? SpelledNote.conventional(root)
        return name.asciiDescription + quality.symbol
    }
}

public enum ChordRecognizer {
    /// Average chroma over each beat (from one beat time to the next).
    public static func beatChroma(_ features: AnalysisFeatures, beats: [Double]) -> [[Float]] {
        guard !beats.isEmpty else { return [] }
        let end = beats.last! + (beats.count > 1 ? beats.last! - beats[beats.count - 2] : 0.5)
        var sums = [[Float]](repeating: [Float](repeating: 0, count: 12), count: beats.count)
        var counts = [Int](repeating: 0, count: beats.count)

        // One pass over the frames, adding each to the beat it falls in. Frames whose window reaches well
        // into the next or previous beat are left out, so a chord change isn't heard a beat early.
        let margin = features.chromaWindow / 4
        var fallback = sums, fallbackCounts = counts
        var beat = 0
        for frame in features.chroma.indices {
            let time = features.chromaTime(frame)
            guard time >= beats[0], time < end else { continue }
            while beat + 1 < beats.count && time >= beats[beat + 1] {
                beat += 1
            }
            let beatEnd = beat + 1 < beats.count ? beats[beat + 1] : end
            vDSP.add(fallback[beat], features.chroma[frame], result: &fallback[beat])
            fallbackCounts[beat] += 1
            if time - beats[beat] >= margin && beatEnd - time >= margin {
                vDSP.add(sums[beat], features.chroma[frame], result: &sums[beat])
                counts[beat] += 1
            }
        }
        // Very short beats may have no frame clear of the edges; use every frame in them instead
        for index in beats.indices where counts[index] == 0 {
            sums[index] = fallback[index]
            counts[index] = fallbackCounts[index]
        }
        return zip(sums, counts).map { sum, count in
            count > 0 ? vDSP.divide(sum, Float(count)) : sum
        }
    }

    /// The likeliest chord on each beat, smoothed so chords last (and change more readily on downbeats),
    /// then merged into runs. `downbeat` is the index of a beat that starts a bar.
    public static func recognise(_ beatChroma: [[Float]], beatsPerBar: Int, downbeat: Int) -> [DetectedChord] {
        guard !beatChroma.isEmpty else { return [] }

        struct State { let root: PitchClass?; let quality: DetectedChord.Quality; let template: [Float] }
        var states: [State] = [State(root: nil, quality: .major, template: [])]
        for root in 0..<12 {
            for quality in DetectedChord.Quality.allCases {
                var template = [Float](repeating: 0, count: 12)
                for (offset, weight) in quality.template {
                    template[(root + offset) % 12] = weight
                }
                states.append(State(root: PitchClass(root), quality: quality, template: template))
            }
        }

        // Quiet beats (no harmony) favour "no chord"
        let energies = beatChroma.map { $0.reduce(0, +) }
        let typical = energies.sorted()[energies.count / 2]

        let sharpness: Double = 20
        func emission(_ chroma: [Float], energy: Float, state: State) -> Double {
            if state.root == nil {
                return energy < typical * 0.1 ? 0 : -sharpness * 0.6
            }
            // Sevenths have to beat the triad clearly: a triad's notes alone shouldn't read as a 7th chord
            let penalty = state.quality.template.count > 3 ? 0.03 : 0
            return sharpness * (BeatTracker.cosine(chroma, state.template) - penalty) - (energy < typical * 0.1 ? sharpness : 0)
        }

        let count = states.count
        var scores = states.map { emission(beatChroma[0], energy: energies[0], state: $0) }
        var backlinks: [[Int]] = []
        for beat in 1..<beatChroma.count {
            let isDownbeat = ((beat - downbeat) % beatsPerBar + beatsPerBar) % beatsPerBar == 0
            let change = isDownbeat ? 0.3 : 0.04
            let stay = log(1 - change), move = log(change / Double(count - 1))
            let bestPrevious = scores.indices.max { scores[$0] < scores[$1] }!

            var next = [Double](repeating: 0, count: count)
            var links = [Int](repeating: 0, count: count)
            for state in 0..<count {
                let fromSelf = scores[state] + stay
                let fromBest = scores[bestPrevious] + move
                if fromSelf >= fromBest {
                    next[state] = fromSelf
                    links[state] = state
                } else {
                    next[state] = fromBest
                    links[state] = bestPrevious
                }
                next[state] += emission(beatChroma[beat], energy: energies[beat], state: states[state])
            }
            scores = next
            backlinks.append(links)
        }

        var path = [scores.indices.max { scores[$0] < scores[$1] }!]
        for links in backlinks.reversed() {
            path.append(links[path.last!])
        }
        path.reverse()

        var result: [DetectedChord] = []
        for (beat, state) in path.enumerated() {
            if let last = result.last, last.root == states[state].root, last.quality == states[state].quality {
                result[result.count - 1].beats = last.beats.lowerBound..<(beat + 1)
            } else {
                result.append(DetectedChord(beats: beat..<(beat + 1), root: states[state].root, quality: states[state].quality))
            }
        }
        return result
    }
}

public enum KeyFinder {
    // Krumhansl–Kessler key profiles, from C
    static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// The key whose profile best matches the total pitch-class energy.
    public static func key(_ chroma: [[Float]]) -> Key? {
        var totals = [Double](repeating: 0, count: 12)
        for frame in chroma {
            let sum = frame.reduce(0, +)
            guard sum > 0 else { continue }
            for pitchClass in 0..<12 {
                totals[pitchClass] += Double(frame[pitchClass] / sum)
            }
        }
        guard totals.contains(where: { $0 > 0 }) else { return nil }

        var best: (key: Key, score: Double)?
        for tonic in 0..<12 {
            for (quality, profile) in [(KeyQuality.major, majorProfile), (.minor, minorProfile)] {
                let rotated = (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
                let score = correlation(totals, rotated)
                if best == nil || score > best!.score {
                    best = (Key(conventional: PitchClass(tonic), quality), score)
                }
            }
        }
        return best?.key
    }

    static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let meanA = a.reduce(0, +) / Double(a.count), meanB = b.reduce(0, +) / Double(b.count)
        var top = 0.0, sumA = 0.0, sumB = 0.0
        for (x, y) in zip(a, b) {
            top += (x - meanA) * (y - meanB)
            sumA += (x - meanA) * (x - meanA)
            sumB += (y - meanB) * (y - meanB)
        }
        return sumA > 0 && sumB > 0 ? top / (sumA * sumB).squareRoot() : 0
    }
}
