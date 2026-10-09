import XCTest
import CoreMIDI
import AVFoundation
@testable import SpotCore

final class TempoClockTests: XCTestCase {
    func testConversions() {
        let clock = TempoClock(bpm: 120)
        XCTAssertEqual(clock.secondsPerBeat, 0.5)
        XCTAssertEqual(clock.seconds(forBeats: 4), 2)
        XCTAssertEqual(clock.beats(forSeconds: 3), 6)
    }

    func testBarAndBeat() {
        let clock = TempoClock(bpm: 90, beatsPerBar: 4)
        XCTAssertTrue(clock.barAndBeat(0) == (1, 1))
        XCTAssertTrue(clock.barAndBeat(3.9) == (1, 4))
        XCTAssertTrue(clock.barAndBeat(4) == (2, 1))
        XCTAssertTrue(clock.barAndBeat(13.5) == (4, 2))
        // A one-bar count-in reads as bar 0
        XCTAssertTrue(clock.barAndBeat(-4) == (0, 1))
        XCTAssertTrue(clock.barAndBeat(-0.5) == (0, 4))
        XCTAssertTrue(TempoClock(bpm: 90, beatsPerBar: 3).barAndBeat(4) == (2, 2))
    }

    func testMetronomeClicks() {
        let clicks = Metronome.clicks(from: -4, to: 1.5, beatsPerBar: 4)
        XCTAssertEqual(clicks.map(\.beat), [-4, -3, -2, -1, 0, 1])
        XCTAssertEqual(clicks.map(\.isAccent), [true, false, false, false, true, false])

        // Windows don't repeat or skip clicks at their edges
        let first = Metronome.clicks(from: 0, to: 2, beatsPerBar: 4)
        let second = Metronome.clicks(from: 2, to: 4.0001, beatsPerBar: 4)
        XCTAssertEqual((first + second).map(\.beat), [0, 1, 2, 3, 4])
        XCTAssertEqual(Metronome.clicks(from: 0.2, to: 0.9, beatsPerBar: 4), [])
        XCTAssertEqual(Metronome.clicks(from: 1, to: 1, beatsPerBar: 4), [])
    }
}

final class AuditionTests: XCTestCase {
    func testChordIsStrummedLowToHigh() {
        let events = Audition.chord([48, 52, 55], strum: 0.05, duration: 1)
        XCTAssertEqual(events.map(\.note), [48, 52, 55])
        XCTAssertEqual(events.map(\.time), [0, 0.05, 0.1])
        // Every note stops together
        XCTAssertEqual(Set(events.map { (($0.time + $0.duration) * 1000).rounded() }).count, 1)
    }

    func testSequenceGoesUpAndDown() {
        let events = Audition.sequence([60, 62, 64], noteLength: 0.25)
        XCTAssertEqual(events.map(\.note), [60, 62, 64, 62, 60])
        XCTAssertEqual(events.map(\.time), [0, 0.25, 0.5, 0.75, 1.0])
        XCTAssertTrue(events.allSatisfy { $0.duration < 0.25 })
        XCTAssertEqual(Audition.sequence([60], noteLength: 0.25).map(\.note), [60])
    }

    func testShapeEvents() throws {
        let library = try LibraryBundle.builtIn()
        let fretboard = Fretboard()
        let major = library.chords.first { $0.id == "builtin.chord.major" }!
        let openC = ShapeGenerator.chordVoicings(major, root: PitchClass(0), fretboard: fretboard)
            .first { $0.system == "Open" && $0.notes.count == 5 }!
        let placement = openC.placements(root: PitchClass(0), on: fretboard)[0]

        let events = Audition.events(for: openC, placement: placement, on: fretboard, clock: TempoClock(bpm: 120))
        // x32010: C3 E3 G3 C4 E4
        XCTAssertEqual(events.map(\.note), [48, 52, 55, 60, 64])

        let scale = ShapeGenerator.scalePositions(library.scales[0], fretboard: fretboard)[0]
        let scaleEvents = Audition.events(for: scale, placement: scale.placements(root: PitchClass(4), on: fretboard)[0],
                                          on: fretboard, clock: TempoClock(bpm: 120))
        XCTAssertEqual(scaleEvents.count, 18 + 17)
        XCTAssertEqual(scaleEvents[1].time, 0.25)   // eighth notes at 120
    }
}

final class HostTimeTests: XCTestCase {
    func testRoundTrip() {
        let start = HostTime.now
        let later = HostTime.adding(1.5, to: start)
        XCTAssertEqual(HostTime.seconds(from: start, to: later), 1.5, accuracy: 0.000_01)
        XCTAssertEqual(HostTime.seconds(from: later, to: start), -1.5, accuracy: 0.000_01)
        XCTAssertEqual(HostTime.adding(-1.5, to: later), start, accuracy: 100)
    }
}

final class MIDIOutputTests: XCTestCase {
    func testWordEncoding() {
        // Note on, channel 3, middle C, velocity 100
        XCTAssertEqual(MIDIOutput.word(status: 0x90, channel: 2, 60, 100), 0x2092_3C64)
        // Out-of-range values are clamped to 7 bits
        XCTAssertEqual(MIDIOutput.word(status: 0x80, channel: 0, 200, -5), 0x2080_7F00)
    }

    /// Listens to the "Spot" virtual source and checks a note arrives.
    func testVirtualSourceDeliversNotes() throws {
        let output: MIDIOutput
        do {
            output = try MIDIOutput(name: "Spot Test \(UUID().uuidString.prefix(6))")
        } catch {
            throw XCTSkip("CoreMIDI isn't available here: \(error)")
        }
        output.channel = 4

        let received = expectation(description: "note received")
        received.assertForOverFulfill = false
        var words: [UInt32] = []
        let lock = NSLock()

        var client = MIDIClientRef()
        var port = MIDIPortRef()
        XCTAssertEqual(MIDIClientCreateWithBlock("Spot test listener" as CFString, &client) { _ in }, noErr)
        XCTAssertEqual(MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port) { list, _ in
            for packet in list.unsafeSequence() where packet.pointee.wordCount > 0 {
                lock.lock()
                words.append(packet.pointee.words.0)
                lock.unlock()
                received.fulfill()
            }
        }, noErr)
        defer {
            MIDIPortDispose(port)
            MIDIClientDispose(client)
        }

        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        XCTAssertEqual(MIDIObjectFindByUniqueID(output.sourceUniqueID, &object, &type), noErr)
        XCTAssertEqual(MIDIPortConnectSource(port, MIDIEndpointRef(object), nil), noErr)

        output.noteOn(64, velocity: 90)
        wait(for: [received], timeout: 3)

        lock.lock()
        XCTAssertEqual(words.first, MIDIOutput.word(status: 0x90, channel: 4, 64, 90))
        lock.unlock()
    }
}

final class ClickPlayerTests: XCTestCase {
    func testClickBuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = ClickPlayer.makeClick(frequency: 1_000, format: format, length: 0.04)
        XCTAssertEqual(buffer.frameLength, 1_920)

        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        XCTAssertEqual(samples.first, 0)
        XCTAssertLessThanOrEqual(samples.map(abs).max()!, 0.8)
        XCTAssertGreaterThan(samples.prefix(200).map(abs).max()!, 0.5)       // loud at the start
        XCTAssertLessThan(samples.suffix(100).map(abs).max()!, 0.05)        // decayed by the end
    }
}
