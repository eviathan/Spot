import XCTest
@testable import SpotCore

/// Synthetic recordings with known answers.
enum TestAudio {
    static let sampleRate = 44_100.0

    /// Beats at `bpm` from `offset`: a low kick on each downbeat, a short high tick on the others.
    static func clickTrack(bpm: Double, offset: Double, seconds: Double, beatsPerBar: Int = 4) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
        var generator = SystemRandomNumberGenerator()
        var beat = 0
        var time = offset
        while time < seconds - 0.2 {
            let start = Int(time * sampleRate)
            if beat % beatsPerBar == 0 {
                for i in 0..<Int(0.12 * sampleRate) where start + i < samples.count {
                    let t = Double(i) / sampleRate
                    samples[start + i] += Float(sin(2 * .pi * 60 * t) * exp(-t * 30) * 0.9)
                }
            }
            for i in 0..<Int(0.03 * sampleRate) where start + i < samples.count {
                let t = Double(i) / sampleRate
                samples[start + i] += Float.random(in: -1...1, using: &generator) * Float(exp(-t * 150) * 0.5)
            }
            beat += 1
            time += 60 / bpm
        }
        return samples
    }

    /// Chords as stacks of notes with a few harmonics, each lasting `beatsEach` beats at `bpm`.
    static func chords(_ chords: [[Int]], bpm: Double, beatsEach: Int, offset: Double = 0) -> [Float] {
        let chordSeconds = 60 / bpm * Double(beatsEach)
        let total = offset + chordSeconds * Double(chords.count) + 0.5
        var samples = [Float](repeating: 0, count: Int(total * sampleRate))
        for (index, notes) in chords.enumerated() {
            let start = Int((offset + Double(index) * chordSeconds) * sampleRate)
            let length = Int(chordSeconds * sampleRate)
            for midi in notes {
                let frequency = 440 * pow(2, Double(midi - 69) / 12)
                for i in 0..<length where start + i < samples.count {
                    let t = Double(i) / sampleRate
                    let envelope = min(1, t * 50) * exp(-t * 0.8)
                    var value = 0.0
                    for harmonic in 1...4 {
                        value += sin(2 * .pi * frequency * Double(harmonic) * t) / Double(harmonic * harmonic)
                    }
                    samples[start + i] += Float(value * envelope * 0.12)
                }
            }
        }
        return samples
    }

    static func audio(_ samples: [Float]) -> AudioData {
        AudioData(channels: [samples, samples], sampleRate: sampleRate)
    }
}

final class BeatTrackingTests: XCTestCase {
    func testTempoBeatsAndBarOne() throws {
        let truth = (0..<60).map { 0.37 + Double($0) * 0.6 }   // 100 bpm
        let audio = TestAudio.audio(TestAudio.clickTrack(bpm: 100, offset: 0.37, seconds: 36))
        let analysis = try XCTUnwrap(AudioAnalysis.analyse(audio, beatsPerBar: 4))

        XCTAssertEqual(analysis.tempoCandidates.first?.bpm ?? 0, 100, accuracy: 2, "\(analysis.tempoCandidates.map(\.bpm))")
        XCTAssertTrue(analysis.tempoCandidates.contains { abs($0.bpm - 50) < 2 } || analysis.tempoCandidates.contains { abs($0.bpm - 200) < 4 })
        XCTAssertEqual(analysis.tempo, 100, accuracy: 1)

        // Every tracked beat is within 30 ms of a real one
        let errors = analysis.beats.map { beat in truth.map { abs($0 - beat) }.min()! }
        XCTAssertLessThan(errors.sorted()[errors.count / 2], 0.015, "median error")
        XCTAssertLessThan(errors.max()!, 0.03, "worst error")
        XCTAssertGreaterThanOrEqual(analysis.beats.count, 55)

        // Bar 1 is the first kick, at 0.37 s
        let markers = analysis.warpMarkers
        XCTAssertEqual(markers.first?.beat, 0)
        XCTAssertEqual(markers.first?.sourceTime ?? 0, 0.37, accuracy: 0.03)
        XCTAssertTrue(markers.dropFirst().allSatisfy { $0.beat.truncatingRemainder(dividingBy: 4) == 0 })
    }

    func testDownbeatShiftAndRetracking() throws {
        let audio = TestAudio.audio(TestAudio.clickTrack(bpm: 100, offset: 0.37, seconds: 24))
        var analysis = try XCTUnwrap(AudioAnalysis.analyse(audio, beatsPerBar: 4))
        let firstDownbeat = analysis.beats[analysis.downbeat]
        analysis.shiftDownbeat(by: 1)
        XCTAssertEqual(analysis.beats[analysis.downbeat] - firstDownbeat, 0.6, accuracy: 0.03)

        analysis.track(tempo: 50)
        XCTAssertEqual(analysis.tempo, 50, accuracy: 1.5)
    }

    func testSilenceDoesNotCrash() {
        let audio = TestAudio.audio([Float](repeating: 0, count: 44_100 * 3))
        let analysis = AudioAnalysis.analyse(audio, beatsPerBar: 4)
        XCTAssertTrue(analysis == nil || analysis!.chords.allSatisfy { $0.root == nil })
    }
}

final class ChordRecognitionTests: XCTestCase {
    // C, Am, F, G with the roots in the bass
    let progression = [[48, 60, 64, 67], [45, 57, 60, 64], [41, 57, 60, 65], [43, 55, 59, 62]]

    func testRecognisesTriadsOnKnownBeats() throws {
        let audio = TestAudio.audio(TestAudio.chords(progression + progression, bpm: 120, beatsEach: 4))
        let features = try XCTUnwrap(AnalysisFeatures.compute(audio))
        let beats = (0..<32).map { Double($0) * 0.5 }
        let chroma = ChordRecognizer.beatChroma(features, beats: beats)
        let chords = ChordRecognizer.recognise(chroma, beatsPerBar: 4, downbeat: 0)

        let symbols = chords.compactMap { $0.symbol(in: nil) }
        XCTAssertEqual(symbols, ["C", "Am", "F", "G", "C", "Am", "F", "G"], "\(chords)")
        XCTAssertEqual(chords.map(\.beats.lowerBound), [0, 4, 8, 12, 16, 20, 24, 28])
        XCTAssertEqual(KeyFinder.key(features.chroma)?.description, "C major")
    }

    func testSeventhChords() throws {
        // Dm7 G7 Cmaj7
        let audio = TestAudio.audio(TestAudio.chords([[50, 60, 62, 65, 69], [43, 59, 62, 65, 67], [48, 59, 60, 64, 67]], bpm: 120, beatsEach: 4))
        let features = try XCTUnwrap(AnalysisFeatures.compute(audio))
        let chroma = ChordRecognizer.beatChroma(features, beats: (0..<12).map { Double($0) * 0.5 })
        let symbols = ChordRecognizer.recognise(chroma, beatsPerBar: 4, downbeat: 0).compactMap { $0.symbol(in: nil) }
        XCTAssertEqual(symbols, ["Dm7", "G7", "Cmaj7"])
    }

    func testWholePipelineOnAMix() throws {
        // Chords plus a click track, starting 0.25 s in
        var samples = TestAudio.chords(progression + progression + progression, bpm: 120, beatsEach: 4, offset: 0.25)
        let clicks = TestAudio.clickTrack(bpm: 120, offset: 0.25, seconds: Double(samples.count) / TestAudio.sampleRate)
        for i in samples.indices where i < clicks.count {
            samples[i] += clicks[i] * 0.5
        }
        let analysis = try XCTUnwrap(AudioAnalysis.analyse(TestAudio.audio(samples), beatsPerBar: 4))
        XCTAssertEqual(analysis.tempo, 120, accuracy: 1.5)
        XCTAssertEqual(analysis.key?.description, "C major")

        let regions = analysis.chordRegions(key: analysis.key)
        XCTAssertEqual(regions.prefix(4).map(\.symbol), ["C", "Am", "F", "G"], "\(regions.map(\.symbol))")
        XCTAssertEqual(regions.prefix(4).map(\.range.start), [0, 4, 8, 12])

        // Through a grid made by hand: bar 1 pinned to the first chord (0.25 s), at 120 bpm
        let handMade = WarpMap(markers: [WarpMarker(sourceTime: 0.25, beat: 0)], tempo: 120)
        let placed = analysis.chordRegions(through: handMade, key: analysis.key, length: 64)
        XCTAssertEqual(placed.prefix(4).map(\.symbol), ["C", "Am", "F", "G"])
        XCTAssertEqual(placed.prefix(4).map(\.range.start), [0, 4, 8, 12])

        // A grid that puts the song two bars in: everything moves with it
        let later = WarpMap(markers: [WarpMarker(sourceTime: 0.25, beat: 8)], tempo: 120)
        XCTAssertEqual(analysis.chordRegions(through: later, key: analysis.key, length: 64).prefix(4).map(\.range.start), [8, 12, 16, 20])
    }
}
