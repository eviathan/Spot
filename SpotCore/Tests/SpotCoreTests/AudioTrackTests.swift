import XCTest
@testable import SpotCore

final class WarpMapTests: XCTestCase {
    func testNoMarkersFollowsTempo() {
        let map = WarpMap(markers: [], tempo: 120)
        XCTAssertEqual(map.sourceTime(atBeat: 4), 2)
        XCTAssertEqual(map.beat(atSourceTime: 3), 6)
    }

    func testOneMarkerShifts() {
        // Beat 1 of the song lands 1.5 s into the recording
        let map = WarpMap(markers: [WarpMarker(sourceTime: 1.5, beat: 0)], tempo: 120)
        XCTAssertEqual(map.sourceTime(atBeat: 0), 1.5)
        XCTAssertEqual(map.sourceTime(atBeat: 4), 3.5)
        XCTAssertEqual(map.beat(atSourceTime: 0.5), -2)
    }

    func testMarkersStretchBetweenAndExtendOutside() {
        let markers = [WarpMarker(sourceTime: 1, beat: 0), WarpMarker(sourceTime: 3, beat: 4), WarpMarker(sourceTime: 4, beat: 8)]
        let map = WarpMap(markers: markers, tempo: 120)
        XCTAssertEqual(map.sourceTime(atBeat: 2), 2)        // halfway between the first two
        XCTAssertEqual(map.sourceTime(atBeat: 6), 3.5)      // the recording speeds up after beat 4
        XCTAssertEqual(map.sourceTime(atBeat: -2), 0)       // before the first: first section's speed
        XCTAssertEqual(map.sourceTime(atBeat: 12), 5)       // after the last: last section's speed
        for beat in stride(from: -4.0, through: 12, by: 0.5) {
            XCTAssertEqual(map.beat(atSourceTime: map.sourceTime(atBeat: beat)), beat, accuracy: 1e-9)
        }
        XCTAssertEqual(map.stretch(atBeat: 1), 1, accuracy: 1e-6)   // 4 beats over 2 s at 120 bpm
        XCTAssertEqual(map.stretch(atBeat: 5), 2, accuracy: 1e-6)   // 4 beats over 1 s: slowed to fit
    }

    func testMarkersMustKeepTimeMovingForwards() {
        var track = AudioTrack(reference: AudioReference(bookmark: nil, lastKnownPath: "", fileName: "x", duration: 10,
                                                         sampleRate: 44_100, channelCount: 2, fingerprint: ""))
        XCTAssertTrue(track.setMarker(WarpMarker(sourceTime: 1, beat: 0)))
        XCTAssertTrue(track.setMarker(WarpMarker(sourceTime: 3, beat: 4)))
        XCTAssertFalse(track.setMarker(WarpMarker(sourceTime: 0.5, beat: 8)), "earlier audio on a later beat")
        XCTAssertEqual(track.warpMarkers.count, 2)
        // Same beat replaces
        XCTAssertTrue(track.setMarker(WarpMarker(sourceTime: 2.5, beat: 4)))
        XCTAssertEqual(track.warpMarkers.map(\.sourceTime), [1, 2.5])
        // Moving a marker keeps its id
        var moved = track.warpMarkers[1]
        moved.beat = 6
        XCTAssertTrue(track.setMarker(moved))
        XCTAssertEqual(track.warpMarkers.map(\.beat), [0, 6])
    }

    func testSequenceFileKeepsAudio() throws {
        var sequence = ChordSequence()
        sequence.audio = AudioTrack(reference: AudioReference(bookmark: Data([1, 2]), lastKnownPath: "/a/b.wav", fileName: "b.wav",
                                                              duration: 3, sampleRate: 48_000, channelCount: 2, fingerprint: "abc"),
                                    warpMarkers: [WarpMarker(sourceTime: 0.2, beat: 0)], gain: -3)
        sequence.practiceRate = 0.75
        XCTAssertEqual(try JSONDecoder().decode(ChordSequence.self, from: sequence.encoded()), sequence)

        let old = #"{"version": 1, "tempo": 100, "beatsPerBar": 4, "lengthInBars": 4}"#
        let decoded = try JSONDecoder().decode(ChordSequence.self, from: Data(old.utf8))
        XCTAssertNil(decoded.audio)
        XCTAssertEqual(decoded.practiceRate, 1)
    }
}

final class AudioDataTests: XCTestCase {
    private func sine(frequency: Double, seconds: Double, sampleRate: Double = 44_100, channels: Int = 2) -> AudioData {
        let frames = Int(seconds * sampleRate)
        let samples = (0..<frames).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate) * 0.5) }
        return AudioData(channels: Array(repeating: samples, count: channels), sampleRate: sampleRate)
    }

    func testBufferPadsOutsideTheAudio() throws {
        let audio = AudioData(channels: [[1, 2, 3]], sampleRate: 10)
        let buffer = try XCTUnwrap(audio.buffer(frames: -2..<4))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 6)), [0, 0, 1, 2, 3, 0])
    }

    func testPeaks() {
        let audio = AudioData(channels: [[0, 0.5, -0.25, 0], [0, 0.5, -0.75, 0]], sampleRate: 4)
        let peaks = WaveformPeaks(audio, samplesPerBlock: 2)
        XCTAssertEqual(peaks.maximums, [0.5, 0])
        XCTAssertEqual(peaks.minimums, [0, -0.5])
        XCTAssertTrue(peaks.range(from: 0, to: 1) == (-0.5, 0.5))
    }

    /// Counts zero crossings to estimate the frequency of a stretch of samples.
    private func frequency(_ samples: ArraySlice<Float>, sampleRate: Double) -> Double {
        let crossings = zip(samples, samples.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        return Double(crossings) / (Double(samples.count) / sampleRate)
    }

    func testRenderWithoutMarkersKeepsTimingAndPitch() throws {
        let source = sine(frequency: 440, seconds: 2)
        let rendered = try XCTUnwrap(WarpRenderer.render(source, map: WarpMap(markers: [], tempo: 120), tempo: 120, beats: 4))
        XCTAssertEqual(rendered.audio.frameCount, 88_200)
        let middle = rendered.audio.channels[0][22_050..<66_150]
        XCTAssertEqual(frequency(middle, sampleRate: 44_100), 440, accuracy: 5)
    }

    func testStretchingKeepsPitchAndMovesEvents() throws {
        // A click half a second in, pinned to beat 2 (1 s at 120 bpm): the audio is stretched to twice as long
        var samples = sine(frequency: 220, seconds: 3).channels[0].map { $0 * 0.2 }
        for i in 22_050..<22_150 { samples[i] = 1 }
        let source = AudioData(channels: [samples], sampleRate: 44_100)
        let map = WarpMap(markers: [WarpMarker(sourceTime: 0, beat: 0), WarpMarker(sourceTime: 0.5, beat: 2)], tempo: 120)

        let rendered = try XCTUnwrap(WarpRenderer.render(source, map: map, tempo: 120, beats: 4))
        let output = rendered.audio.channels[0]
        let loudest = output.indices.max { abs(output[$0]) < abs(output[$1]) }!
        XCTAssertEqual(Double(loudest) / 44_100, 1.0, accuracy: 0.01, "click should land on beat 2")

        // Pitch is unchanged even though the first half second is stretched to a full second
        XCTAssertEqual(frequency(output[4_410..<39_690], sampleRate: 44_100), 220, accuracy: 6)
    }

    func testRenderSpeed() throws {
        let source = sine(frequency: 440, seconds: 30)
        let start = Date()
        _ = WarpRenderer.render(source, map: WarpMap(markers: [], tempo: 120), tempo: 100, beats: 50)
        let elapsed = Date().timeIntervalSince(start)
        print("RENDER 30 s stereo in \(String(format: "%.2f", elapsed)) s")
    }
}
