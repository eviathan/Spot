import XCTest
import AVFoundation
@testable import SpotCore

/// The track player's audio thread, run by hand: what it plays at a start, a loop going round, a new render
/// and a stop, and that none of them jumps (a click).
final class TrackPlayerRendererTests: XCTestCase {
    private let sampleRate = 48_000.0
    /// 120 bpm: 24,000 frames a beat.
    private let tempo = 120.0
    private let bufferFrames = 512

    private func sine(frequency: Double = 440, beats: Double = 8, phase: Double = 0) -> RenderedAudio {
        let count = Int(beats * sampleRate * 60 / tempo)
        let samples = (0..<count).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate + phase) * 0.8) }
        return RenderedAudio(audio: AudioData(channels: [samples], sampleRate: sampleRate), tempo: tempo)
    }

    /// Renders `buffers` buffers, as the engine would, the first heard at `start`.
    private func render(_ renderer: Renderer, buffers: Int, from start: UInt64 = HostTime.now) -> [Float] {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferFrames))!
        buffer.frameLength = AVAudioFrameCount(bufferFrames)
        var output: [Float] = []
        for index in 0..<buffers {
            var time = AudioTimeStamp()
            time.mFlags = .hostTimeValid
            time.mHostTime = HostTime.adding(Double(index * bufferFrames) / sampleRate, to: start)
            renderer.render(time, frames: bufferFrames, sampleRate: sampleRate,
                            into: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList))
            output += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: bufferFrames)
        }
        return output
    }

    /// The biggest step from one sample to the next: a 440 Hz sine at 0.8 moves at most about 0.046.
    private func largestStep(_ samples: [Float]) -> Float {
        zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }

    func testStartsAtItsTimeWithAFadeIn() {
        let commands = CommandQueue()
        let renderer = Renderer(commands: commands)
        let audio = sine()
        let now = HostTime.now
        // 100 frames into the first buffer, from beat 1
        commands.push(.start(Source(audio), beat: 1, hostTime: HostTime.adding(100 / sampleRate, to: now)))
        let output = render(renderer, buffers: 4, from: now)

        XCTAssertEqual(output.prefix(100).map(abs).max(), 0)
        // After the fade, exactly the recording from beat 1
        let fade = Int(sampleRate * TrackPlayer.fadeLength)
        let first = audio.frame(atBeat: 1)
        for offset in fade..<(fade + 500) {
            XCTAssertEqual(output[100 + offset], audio.audio.channels[0][first + offset], accuracy: 1e-6)
        }
        XCTAssertLessThan(largestStep(output), 0.05)
    }

    func testStartingLateCatchesUp() {
        let commands = CommandQueue()
        let renderer = Renderer(commands: commands)
        let audio = sine()
        let now = HostTime.now
        // Due 1,000 frames before this buffer: it starts that far in
        commands.push(.start(Source(audio), beat: 0, hostTime: HostTime.adding(-1000 / sampleRate, to: now)))
        let output = render(renderer, buffers: 2, from: now)
        let fade = Int(sampleRate * TrackPlayer.fadeLength)
        XCTAssertEqual(output[fade], audio.audio.channels[0][1000 + fade], accuracy: 1e-6)
    }

    func testLoopGoesRoundSmoothly() {
        let commands = CommandQueue()
        let renderer = Renderer(commands: commands)
        let audio = sine()
        let now = HostTime.now
        commands.push(.start(Source(audio), beat: 0, hostTime: now))
        // Round from part way through a cycle (so the join would click without a crossfade)
        let loopEnd = 0.1234
        commands.push(.jump(at: loopEnd, to: 0))
        let output = render(renderer, buffers: 20, from: now)

        let endFrame = audio.frame(atBeat: loopEnd)
        let fade = Int(sampleRate * TrackPlayer.fadeLength)
        // Once the crossfade's done: the recording from the loop start again
        for offset in fade..<(fade + 500) {
            XCTAssertEqual(output[endFrame + offset], audio.audio.channels[0][offset], accuracy: 1e-6)
        }
        XCTAssertLessThan(largestStep(output), 0.05)
    }

    func testOverdueJumpGoesNowAsFarOn() {
        let commands = CommandQueue()
        let renderer = Renderer(commands: commands)
        let audio = sine()
        let now = HostTime.now
        commands.push(.start(Source(audio), beat: 0, hostTime: now))
        _ = render(renderer, buffers: 10, from: now)
        // Asked for after it's passed: 5,120 frames played, the jump was at 4,000
        commands.push(.jump(at: 4000 / audio.framesPerBeat, to: 0))
        let output = render(renderer, buffers: 2, from: HostTime.adding(5120 / sampleRate, to: now))
        let fade = Int(sampleRate * TrackPlayer.fadeLength)
        XCTAssertEqual(output[fade], audio.audio.channels[0][1120 + fade], accuracy: 1e-6)
    }

    func testNewRenderCrossfadesIn() {
        let commands = CommandQueue()
        let renderer = Renderer(commands: commands)
        let first = sine()
        // Different enough to click if it were switched straight over
        let second = sine(phase: .pi / 2)
        let now = HostTime.now
        commands.push(.start(Source(first), beat: 0, hostTime: now))
        var output = render(renderer, buffers: 3, from: now)
        commands.push(.replace(Source(second)))
        output += render(renderer, buffers: 3, from: HostTime.adding(Double(3 * bufferFrames) / sampleRate, to: now))

        let fade = Int(sampleRate * TrackPlayer.fadeLength)
        let at = 3 * bufferFrames + fade
        XCTAssertEqual(output[at], second.audio.channels[0][at], accuracy: 1e-6)
        XCTAssertLessThan(largestStep(output), 0.05)
    }

    func testStopFadesOut() {
        let commands = CommandQueue()
        let renderer = Renderer(commands: commands)
        let now = HostTime.now
        commands.push(.start(Source(sine()), beat: 0, hostTime: now))
        var output = render(renderer, buffers: 3, from: now)
        commands.push(.stop)
        output += render(renderer, buffers: 3, from: HostTime.adding(Double(3 * bufferFrames) / sampleRate, to: now))

        let fade = Int(sampleRate * TrackPlayer.fadeLength)
        // (Silent but for rounding in the gain ramp)
        XCTAssertLessThan(output.suffix(from: 3 * bufferFrames + fade + 1).map(abs).max()!, 1e-5)
        XCTAssertLessThan(largestStep(output), 0.05)
    }

    func testVolumeChangesSmoothly() {
        let commands = CommandQueue()
        let renderer = Renderer(commands: commands)
        let now = HostTime.now
        commands.push(.start(Source(sine()), beat: 0, hostTime: now))
        var output = render(renderer, buffers: 3, from: now)
        commands.setGain(0.1)
        output += render(renderer, buffers: 3, from: HostTime.adding(Double(3 * bufferFrames) / sampleRate, to: now))
        XCTAssertLessThan(largestStep(output), 0.05)
        XCTAssertLessThan(output.suffix(bufferFrames).map(abs).max()!, 0.081)
    }
}
