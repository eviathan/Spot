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
                                                         sampleRate: 44_100, channelCount: 2, fingerprint: ""), tempo: 120)
        XCTAssertEqual(track.warpMarkers.map(\.beat), [0], "starts with one marker")
        XCTAssertTrue(track.setMarker(WarpMarker(sourceTime: 1, beat: 0)), "same beat replaces it")
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
                                    tempo: 96, warpMarkers: [WarpMarker(sourceTime: 0.2, beat: 0)], gain: -3)
        XCTAssertEqual(try JSONDecoder().decode(ChordSequence.self, from: sequence.encoded()), sequence)

        let old = #"{"version": 1, "tempo": 100, "beatsPerBar": 4, "lengthInBars": 4}"#
        let decoded = try JSONDecoder().decode(ChordSequence.self, from: Data(old.utf8))
        XCTAssertNil(decoded.audio)
        XCTAssertEqual(decoded.tempo, 100)
    }

    /// Before recordings had their own tempo, the sequence's was the recording's and a practice speed slowed both.
    func testOlderFilesKeepTheirTimingAndSpeed() throws {
        let old = #"""
        {"version": 1, "tempo": 100, "beatsPerBar": 4, "lengthInBars": 4, "practiceRate": 0.75,
         "audio": {"reference": {"lastKnownPath": "/a.wav", "fileName": "a.wav", "duration": 3, "sampleRate": 44100,
                                 "channelCount": 2, "fingerprint": "x"},
                   "warpMarkers": [], "gain": 0, "isMuted": false}}
        """#
        let decoded = try JSONDecoder().decode(ChordSequence.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.audio?.tempo, 100, "the recording keeps the tempo it was lined up at")
        XCTAssertEqual(decoded.tempo, 75, "and plays at the speed it was practised at")
        XCTAssertEqual(decoded.audio?.warpMarkers.map(\.beat), [0])
        XCTAssertEqual(decoded.audio?.warpMarkers.map(\.sourceTime), [0])
        let saved = try JSONSerialization.jsonObject(with: decoded.encoded()) as? [String: Any]
        XCTAssertNil(saved?["practiceRate"], "saved without it")
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

/// Warping like a clip in Live: the recording's own tempo, a marker that's always there, and section tempos.
final class WarpClipTests: XCTestCase {
    private func track(tempo: Double = 120) -> AudioTrack {
        AudioTrack(reference: AudioReference(bookmark: nil, lastKnownPath: "", fileName: "x", duration: 20,
                                             sampleRate: 44_100, channelCount: 1, fingerprint: ""), tempo: tempo)
    }

    func testThereIsAlwaysAMarker() throws {
        var track = track()
        let first = try XCTUnwrap(track.warpMarkers.first)
        track.removeMarker(first.id)
        XCTAssertEqual(track.warpMarkers.count, 1, "the last marker can't be removed")

        // Dragging the only marker moves the whole recording without stretching it
        var moved = first
        moved.beat = 2
        track.setMarker(moved)
        XCTAssertEqual(track.map.sourceTime(atBeat: 2), 0)
        XCTAssertEqual(track.map.sourceTime(atBeat: 6), 2, "still 0.5 s per beat at 120")

        track.setMarker(WarpMarker(sourceTime: 4, beat: 10))
        track.setMarker(WarpMarker(sourceTime: 6, beat: 14))
        track.removeAllMarkers()
        XCTAssertEqual(track.warpMarkers, [moved], "clearing keeps the first")
    }

    func testSectionTempos() {
        var track = track(tempo: 100)
        track.setMarker(WarpMarker(sourceTime: 2, beat: 4))     // 4 beats in 2 s: 120 bpm
        track.setMarker(WarpMarker(sourceTime: 4, beat: 7))     // 3 beats in 2 s: 90 bpm
        XCTAssertEqual(track.segmentTempo(atBeat: -1), 100, "before the first marker: its own tempo")
        XCTAssertEqual(track.segmentTempo(atBeat: 1), 120, accuracy: 1e-9)
        XCTAssertEqual(track.segmentTempo(atBeat: 5), 90, accuracy: 1e-9)
        XCTAssertEqual(track.segmentTempo(atBeat: 9), 100, "after the last: its own tempo")

        // Setting a section's tempo moves its end marker, and the later ones keep their tempos
        track.setSegmentTempo(60, atBeat: 1)
        XCTAssertEqual(track.warpMarkers.map(\.beat), [0, 2, 5])
        XCTAssertEqual(track.segmentTempo(atBeat: 1), 60, accuracy: 1e-9)
        XCTAssertEqual(track.segmentTempo(atBeat: 3), 90, accuracy: 1e-9)

        // Outside the markers it's the recording's tempo
        track.setSegmentTempo(110, atBeat: 20)
        XCTAssertEqual(track.tempo, 110)
    }

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

    func testAtItsOwnTempoTheRecordingIsCopiedExactly() throws {
        let source = clicks(at: [0.3, 1.3], seconds: 3)
        // Bar 1 is 0.3 s in, and nothing is stretched
        let map = WarpMap(markers: [WarpMarker(sourceTime: 0.3, beat: 0)], tempo: 120)
        let rendered = try XCTUnwrap(WarpRenderer.render(source, map: map, tempo: 120, from: -1, to: 4))
        let offset = Int(0.3 * 44_100) - 22_050    // beat -1 is 0.2 s before
        for i in stride(from: 0, to: rendered.audio.frameCount, by: 97) {
            let j = i + offset
            let expected: Float = j >= 0 && j < source.frameCount ? source.channels[0][j] : 0
            XCTAssertEqual(rendered.audio.channels[0][i], expected, "frame \(i)")
        }
    }

    func testOnlyTheStretchedSectionIsStretched() throws {
        // Clicks every half second; the section from 1 s to 2 s is pinned to beats 2...6 (twice as long)
        let source = clicks(at: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5], seconds: 4.5)
        let map = WarpMap(markers: [WarpMarker(sourceTime: 1, beat: 2), WarpMarker(sourceTime: 2, beat: 6)], tempo: 120)
        let fast = try XCTUnwrap(WarpRenderer.render(source, map: map, tempo: 120, from: 0, to: 9))
        let found = onsets(fast)
        let expected: [Double] = [0, 1, 2, 4, 6, 7, 8]
        XCTAssertEqual(found.count, expected.count, "\(found)")
        for (x, y) in zip(found, expected) {
            XCTAssertEqual(x, y, accuracy: 0.02)
        }
    }
}

final class RenderedAudioTests: XCTestCase {
    func testABackwardsRangeIsNothingNotACrash() {
        let rendered = RenderedAudio(audio: AudioData(channels: [[Float](repeating: 0.1, count: 44_100)], sampleRate: 44_100), tempo: 120)
        XCTAssertNil(rendered.buffer(fromBeat: 1.5, toBeat: 1))
        XCTAssertNil(rendered.buffer(fromBeat: 1, toBeat: 1))
        XCTAssertEqual(rendered.buffer(fromBeat: 0, toBeat: 1)?.frameLength, 22_050)
    }
}
