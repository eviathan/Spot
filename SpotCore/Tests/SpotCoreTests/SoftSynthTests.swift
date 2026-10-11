import XCTest
import AVFoundation
@testable import SpotCore

final class SoftSynthTests: XCTestCase {
    /// Renders the synth offline at real-time pace (its queue goes by the clock) and returns where sound first
    /// appears, in frames, after a note sent `delay` seconds ahead.
    private func onset(sentAhead delay: Double) throws -> Int? {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        let synth = try SoftSynth(engine: engine, start: false)
        try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
        // The synth loads an instrument's samples when it's first played, in the background (offline rendering
        // runs ahead of that): play one note and let it load, then silence it and render until quiet
        synth.send([0x90, 40, 100])
        _ = try engine.renderOffline(512, to: buffer)
        Thread.sleep(forTimeInterval: 1)
        synth.allNotesOff()
        for _ in 0..<400 { _ = try engine.renderOffline(512, to: buffer) }

        let started = HostTime.now
        synth.send([0x90, 52, 120], atHostTime: delay > 0 ? HostTime.adding(delay, to: started) : 0)
        var frame = 0
        for index in 0..<100 {
            let due = HostTime.adding(Double(index * 512) / 48000, to: started)
            while HostTime.now < due { usleep(200) }
            _ = try engine.renderOffline(512, to: buffer)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            if let first = samples.firstIndex(where: { abs($0) > 0.0005 }) {
                return frame + first
            }
            frame += Int(buffer.frameLength)
        }
        return nil
    }

    func testPlaysANote() throws {
        XCTAssertNotNil(try onset(sentAhead: 0), "the built-in guitar should make a sound")
    }

    /// Notes are sent ahead of time; they must sound when they're due, not when they arrive (nor be dropped).
    func testHonoursScheduledTimes() throws {
        let now = try XCTUnwrap(onset(sentAhead: 0))
        let later = try XCTUnwrap(onset(sentAhead: 0.1))   // the playback lookahead
        print("SYNTH onset now \(now), sent 0.1 s ahead \(later)")
        // Within a buffer or so (the pacing here is by sleeping)
        XCTAssertEqual(Double(later - now), 4800, accuracy: 600)
    }
}
