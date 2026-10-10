import XCTest
@testable import SpotCore
import AVFoundation

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
        XCTAssertEqual(map.sourceTime(atBeat: -2), 0)       // before the first: not stretched (0.5 s per beat at 120)
        XCTAssertEqual(map.sourceTime(atBeat: 12), 6)       // after the last: not stretched either
        XCTAssertEqual(map.stretch(atBeat: 10), 1, accuracy: 1e-6)
        for beat in stride(from: -4.0, through: 12, by: 0.5) {
            XCTAssertEqual(map.beat(atSourceTime: map.sourceTime(atBeat: beat)), beat, accuracy: 1e-9)
        }
        XCTAssertEqual(map.stretch(atBeat: 1), 1, accuracy: 1e-6)   // 4 beats over 2 s at 120 bpm
        XCTAssertEqual(map.stretch(atBeat: 5), 2, accuracy: 1e-6)   // 4 beats over 1 s: slowed to fit
    }

    /// Moving a marker only stretches the audio between it and its neighbours; beyond the last marker
    /// the audio just moves along with it at its own speed.
    func testMovingTheLastMarkerDoesNotStretchTheTail() {
        let before = WarpMap(markers: [WarpMarker(sourceTime: 0, beat: 0), WarpMarker(sourceTime: 2, beat: 4)], tempo: 120)
        let after = WarpMap(markers: [WarpMarker(sourceTime: 0, beat: 0), WarpMarker(sourceTime: 2, beat: 6)], tempo: 120)
        // One second of audio after the last marker is still two beats long
        XCTAssertEqual(before.beat(atSourceTime: 3) - before.beat(atSourceTime: 2), 2, accuracy: 1e-9)
        XCTAssertEqual(after.beat(atSourceTime: 3) - after.beat(atSourceTime: 2), 2, accuracy: 1e-9)
        // ...but it starts two beats later, along with the marker
        XCTAssertEqual(after.beat(atSourceTime: 3) - before.beat(atSourceTime: 3), 2, accuracy: 1e-9)
        // Between the markers, the audio is stretched to fill six beats instead of four
        XCTAssertEqual(after.stretch(atBeat: 3), 1.5, accuracy: 1e-6)

        // Moving a middle marker leaves everything outside its neighbours alone
        let three = [WarpMarker(sourceTime: 0, beat: 0), WarpMarker(sourceTime: 2, beat: 4), WarpMarker(sourceTime: 4, beat: 8)]
        var moved = three
        moved[1].beat = 5
        let a = WarpMap(markers: three, tempo: 120), b = WarpMap(markers: moved, tempo: 120)
        for beat in [-2.0, 0, 8, 10, 16] {
            XCTAssertEqual(a.sourceTime(atBeat: beat), b.sourceTime(atBeat: beat), accuracy: 1e-9, "beat \(beat)")
        }
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

final class PartialRenderTests: XCTestCase {
    private func clicks(at times: [Double], seconds: Double) -> AudioData {
        var samples = [Float](repeating: 0, count: Int(seconds * 44_100))
        for i in samples.indices { samples[i] = Float(sin(Double(i) * 0.05) * 0.02) }
        for time in times {
            let start = Int(time * 44_100)
            for i in start..<min(start + 80, samples.count) { samples[i] = 0.9 }
        }
        return AudioData(channels: [samples], sampleRate: 44_100)
    }

    private func onsets(_ rendered: RenderedAudio) -> [Double] {
        var result: [Double] = []
        var i = 0
        let samples = rendered.audio.channels[0]
        while i < samples.count {
            if abs(samples[i]) > 0.5 {
                result.append(rendered.startBeat + Double(i) / rendered.framesPerBeat)
                i += 4_410
            } else {
                i += 1
            }
        }
        return result
    }

    func testRendersBeforeBarOne() throws {
        // A pickup half a second before the first marker: it lands on beat -1 at 120 bpm
        let source = clicks(at: [0.2, 0.7, 1.2], seconds: 3)
        let map = WarpMap(markers: [WarpMarker(sourceTime: 0.7, beat: 0)], tempo: 120)
        let rendered = try XCTUnwrap(WarpRenderer.render(source, map: map, tempo: 120, from: -2, to: 4))
        XCTAssertEqual(rendered.startBeat, -2)
        let beats = onsets(rendered)
        XCTAssertEqual(beats.count, 3)
        for (found, expected) in zip(beats, [-1.0, 0, 1]) {
            XCTAssertEqual(found, expected, accuracy: 0.02)
        }
        // Buffers are addressed in beats, wherever the render starts
        let buffer = try XCTUnwrap(rendered.buffer(fromBeat: 0, toBeat: 1))
        XCTAssertEqual(Int(buffer.frameLength), 22_050)
        let start = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 1_100)
        XCTAssertGreaterThan(start.map(abs).max()!, 0.5, "the click on beat 0 is at the start of the buffer")
    }

    func testSpliceMatchesAFullRender() throws {
        let source = clicks(at: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5], seconds: 4.5)
        let before = WarpMap(markers: [WarpMarker(sourceTime: 0, beat: 0), WarpMarker(sourceTime: 2, beat: 4)], tempo: 120)
        var rendered = try XCTUnwrap(WarpRenderer.render(source, map: before, tempo: 120, from: 0, to: 8))

        // Move the second marker: only beats 0..8 around it change; re-render that stretch and splice it in
        let after = WarpMap(markers: [WarpMarker(sourceTime: 0, beat: 0), WarpMarker(sourceTime: 2, beat: 3)], tempo: 120)
        let segment = try XCTUnwrap(WarpRenderer.render(source, map: after, tempo: 120, from: 0, to: 8))
        rendered.splice(segment)
        let full = try XCTUnwrap(WarpRenderer.render(source, map: after, tempo: 120, from: 0, to: 8))

        let a = onsets(rendered), b = onsets(full)
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x, y, accuracy: 0.01)
        }
        // The click that was at 2 s now sits on beat 3
        XCTAssertTrue(a.contains { abs($0 - 3) < 0.02 }, "\(a)")
    }
}

final class RecordingTests: XCTestCase {
    func testTakeWriterRecordsTimingAndLength() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("take-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let writer = try TakeWriter(url: url, format: format)

        let firstTime = HostTime.adding(1, to: HostTime.now)
        for block in 0..<10 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
            buffer.frameLength = 4_800
            for i in 0..<4_800 { buffer.floatChannelData![0][i] = block == 3 ? 0.5 : 0.01 }
            let time = AVAudioTime(hostTime: HostTime.adding(Double(block) * 0.1, to: firstTime))
            try writer.write(buffer, at: time)
        }
        XCTAssertEqual(writer.startHostTime, firstTime)
        XCTAssertEqual(writer.duration, 1, accuracy: 0.001)
        XCTAssertEqual(writer.level, 0.01, accuracy: 0.001)

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 48_000)
    }

    func testTakePlacement() throws {
        // Recorded at 90 bpm (120 at 75%), starting on beat 8
        let take = RecordedTake(name: "Take 1", fileName: "Take 1.caf", startBeat: 8, duration: 4, tempo: 90)
        XCTAssertEqual(take.endBeat, 14)
        XCTAssertEqual(take.offset(atBeat: 11), 2)

        var sequence = ChordSequence()
        sequence.takes = [take]
        XCTAssertEqual(try JSONDecoder().decode(ChordSequence.self, from: sequence.encoded()).takes, [take])
    }

    func testListsInputDevicesWithoutCrashing() {
        // Contents depend on the machine; every listed device must have inputs
        XCTAssertTrue(AudioDevices.inputs().allSatisfy { $0.channelCount > 0 })
    }
}
