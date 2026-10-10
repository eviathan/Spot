import XCTest
@testable import SpotCore

final class ChordSequenceTests: XCTestCase {
    private func summary(_ sequence: ChordSequence) -> String {
        sequence.chords.map { "\($0.symbol)@\(Int($0.range.start))-\(Int($0.range.end))" }.joined(separator: " ")
    }

    func testSettingChordsOverwritesTrimsAndSplits() {
        var sequence = ChordSequence(lengthInBars: 4)
        sequence.setChord("C", in: sequence.bar(0))
        sequence.setChord("F", in: BeatRange(4, 12))
        XCTAssertEqual(summary(sequence), "C@0-4 F@4-12")

        // Overlapping the end of one and the start of the next trims both
        sequence.setChord("G", in: BeatRange(2, 6))
        XCTAssertEqual(summary(sequence), "C@0-2 G@2-6 F@6-12")

        // Inside one chord splits it, and the halves are separate regions
        sequence.setChord("Bb", in: BeatRange(8, 10))
        XCTAssertEqual(summary(sequence), "C@0-2 G@2-6 F@6-8 Bb@8-10 F@10-12")
        XCTAssertEqual(Set(sequence.chords.map(\.id)).count, 5)

        sequence.clearChords(in: BeatRange(5, 9))
        XCTAssertEqual(summary(sequence), "C@0-2 G@2-5 Bb@9-10 F@10-12")

        // Past the end is clamped
        sequence.setChord("E", in: BeatRange(14, 40))
        XCTAssertEqual(sequence.chords.last?.range, BeatRange(14, 16))
    }

    func testLookup() {
        var sequence = ChordSequence(lengthInBars: 4)
        sequence.setChord("Dm7", in: sequence.bar(0))
        sequence.setChord("G7", in: sequence.bar(1))
        sequence.setChord("Cmaj7", in: BeatRange(8, 16))

        XCTAssertEqual(sequence.chord(at: 0)?.symbol, "Dm7")
        XCTAssertEqual(sequence.chord(at: 3.99)?.symbol, "Dm7")
        XCTAssertEqual(sequence.chord(at: 4)?.symbol, "G7")
        XCTAssertNil(sequence.chord(at: 16))
        XCTAssertEqual(sequence.chord(after: 2)?.symbol, "G7")
        XCTAssertEqual(sequence.chord(after: 4)?.symbol, "Cmaj7")
        XCTAssertNil(sequence.chord(after: 8))
    }

    func testSectionsAndLength() {
        var sequence = ChordSequence(lengthInBars: 8)
        sequence.setSection("Verse", in: BeatRange(0, 16))
        sequence.setSection("Chorus", in: BeatRange(16, 32))
        sequence.setSection("Bridge", in: BeatRange(12, 20))
        XCTAssertEqual(sequence.sections.map(\.name), ["Verse", "Bridge", "Chorus"])
        XCTAssertEqual(sequence.section(at: 13)?.name, "Bridge")

        sequence.setChord("C", in: BeatRange(0, 32))
        sequence.loop = BeatRange(8, 24)
        sequence.setLength(bars: 4)
        XCTAssertEqual(sequence.chords.map(\.range), [BeatRange(0, 16)])
        XCTAssertEqual(sequence.sections.map(\.name), ["Verse", "Bridge"])
        XCTAssertEqual(sequence.loop, BeatRange(8, 16))
        sequence.setLength(bars: 2)
        XCTAssertNil(sequence.loop)
    }

    func testFileRoundTrip() throws {
        var sequence = ChordSequence(tempo: 132, beatsPerBar: 3, lengthInBars: 8)
        sequence.setChord("Bb7#9/D", in: sequence.bar(0), scaleId: "builtin.scale.altered")
        sequence.setSection("Intro", in: sequence.bar(0))
        sequence.loop = BeatRange(0, 6)
        sequence.key = Key(SpelledNote("Bb")!, .major)

        let decoded = try JSONDecoder().decode(ChordSequence.self, from: sequence.encoded())
        XCTAssertEqual(decoded, sequence)

        let newer = #"{"version": 99, "tempo": 100, "beatsPerBar": 4, "lengthInBars": 4}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ChordSequence.self, from: Data(newer.utf8)))
    }
}

final class ChordClipTests: XCTestCase {
    func testMovingAndResizingKeepsTheChord() throws {
        var sequence = ChordSequence(lengthInBars: 4)
        sequence.setChord("Dm7", in: BeatRange(0, 4), scaleId: "builtin.scale.dorian")
        sequence.setChord("G7", in: BeatRange(4, 8))
        sequence.setChord("Cmaj7", in: BeatRange(8, 16))
        var g7 = try XCTUnwrap(sequence.chords.first { $0.symbol == "G7" })

        // Shorten to a beat and a half, starting on the "and" of 2
        g7.range = BeatRange(5.5, 7)
        sequence.place(g7)
        XCTAssertEqual(sequence.chords.map(\.symbol), ["Dm7", "G7", "Cmaj7"])
        XCTAssertEqual(sequence.chords[1].range, BeatRange(5.5, 7))
        XCTAssertEqual(sequence.chords[1].id, g7.id)

        // Moving over another chord trims it; the moved chord keeps its pinned scale
        var dm7 = sequence.chords[0]
        dm7.range = BeatRange(6, 10)
        sequence.place(dm7)
        XCTAssertEqual(sequence.chords.map(\.symbol), ["G7", "Dm7", "Cmaj7"])
        XCTAssertEqual(sequence.chords.map(\.range), [BeatRange(5.5, 6), BeatRange(6, 10), BeatRange(10, 16)])
        XCTAssertEqual(sequence.chords[1].scaleId, "builtin.scale.dorian")

        // Clamped to the sequence
        var cmaj7 = sequence.chords[2]
        cmaj7.range = BeatRange(14, 20)
        sequence.place(cmaj7)
        XCTAssertEqual(sequence.chords.last?.range, BeatRange(14, 16))
    }
}
