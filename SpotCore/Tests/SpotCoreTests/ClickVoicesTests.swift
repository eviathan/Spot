import XCTest
import AVFoundation
@testable import SpotCore

/// The metronome's audio thread, run by hand: each click lands on its frame, wherever it falls.
final class ClickVoicesTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let frames = 512
    private let click: [Float] = (0..<100).map { _ in 0.5 }

    private func render(_ voices: ClickVoices, buffers: Int, from start: UInt64) -> [Float] {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        var output: [Float] = []
        for index in 0..<buffers {
            voices.render(at: HostTime.adding(Double(index * frames) / sampleRate, to: start), frames: frames,
                          into: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList))
            output += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: frames)
        }
        return output
    }

    func testClicksLandOnTheirFrames() {
        let queue = ClickQueue()
        let voices = ClickVoices(accent: click, normal: click.map { $0 / 2 }, queue: queue, sampleRate: sampleRate)
        let start = HostTime.now
        // One inside the first buffer, one across a buffer edge
        queue.push(.click(time: HostTime.adding(200 / sampleRate, to: start), accent: true))
        queue.push(.click(time: HostTime.adding(1000 / sampleRate, to: start), accent: false))
        let output = render(voices, buffers: 4, from: start)

        let firstOnset = output.firstIndex { $0 != 0 }
        XCTAssertEqual(Double(firstOnset ?? -1), 200, accuracy: 1)
        XCTAssertEqual(output[250], 0.5)
        XCTAssertEqual(output[1000 + 50], 0.25)
        // Each one's whole length, then silence
        XCTAssertEqual(output[300 + 5], 0)
        XCTAssertEqual(output[1100 + 5], 0)
    }

    func testLateClickSoundsAtOnceAndAVeryLateOneDoesnt() {
        let queue = ClickQueue()
        let voices = ClickVoices(accent: click, normal: click, queue: queue, sampleRate: sampleRate)
        let start = HostTime.now
        queue.push(.click(time: HostTime.adding(-0.01, to: start), accent: true))
        XCTAssertEqual(render(voices, buffers: 1, from: start)[0], 0.5)

        queue.push(.click(time: HostTime.adding(-0.5, to: start), accent: true))
        XCTAssertEqual(render(voices, buffers: 1, from: HostTime.adding(Double(frames) / sampleRate, to: start)).map(abs).max(), 0)
    }

    func testClearForgetsWhatsToComeButLetsOneRingOut() {
        let queue = ClickQueue()
        let long = [Float](repeating: 0.5, count: 2_000)
        let voices = ClickVoices(accent: long, normal: long, queue: queue, sampleRate: sampleRate)
        let start = HostTime.now
        queue.push(.click(time: start, accent: true))
        queue.push(.click(time: HostTime.adding(0.5, to: start), accent: true))
        _ = render(voices, buffers: 1, from: start)
        queue.push(.clear)
        let output = render(voices, buffers: 60, from: HostTime.adding(Double(frames) / sampleRate, to: start))
        // The first carries on to its end; the second never comes
        XCTAssertEqual(output[0], 0.5)
        XCTAssertEqual(output[2_000 - frames - 1], 0.5)
        XCTAssertEqual(output.suffix(from: 2_000 - frames).map(abs).max(), 0)
    }
}
