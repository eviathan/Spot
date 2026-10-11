import XCTest
@testable import SpotCore

final class PatternTests: XCTestCase {
    /// Am C | G F over two bars of 4/4, grouped.
    private func grouped() -> (ChordSequence, UUID) {
        var sequence = ChordSequence(lengthInBars: 16)
        for (index, symbol) in ["Am", "C", "G", "F"].enumerated() {
            sequence.setChord(symbol, in: BeatRange(Double(index * 2), Double(index * 2 + 2)))
        }
        let id = sequence.makePattern(from: BeatRange(0, 8), name: "Verse")!
        return (sequence, id)
    }

    private func symbols(_ sequence: ChordSequence) -> [String] {
        sequence.chords.map(\.symbol)
    }

    func testGroupingKeepsTheChords() {
        let (sequence, _) = grouped()
        XCTAssertEqual(symbols(sequence), ["Am", "C", "G", "F"])
        XCTAssertTrue(sequence.looseChords.isEmpty)
        XCTAssertEqual(sequence.patterns.first?.length, 8)
        XCTAssertEqual(sequence.partName(at: 3), "Verse")
        // Not over another pattern
        var again = sequence
        XCTAssertNil(again.makePattern(from: BeatRange(4, 12)))
    }

    func testStretchingRepeats() {
        var (sequence, id) = grouped()
        sequence.setRange(of: id, to: BeatRange(0, 20))
        XCTAssertEqual(symbols(sequence), ["Am", "C", "G", "F", "Am", "C", "G", "F", "Am", "C"])
        XCTAssertEqual(sequence.chords.last?.range, BeatRange(18, 20))
        // The repeats know where they come from
        XCTAssertEqual(sequence.chordSources[sequence.chords[4].id]?.round, 1)
        // Laid out the same way every time (so the analysis and selection keep hold of them)
        let ids = sequence.chords.map(\.id)
        sequence.rebuild()
        XCTAssertEqual(sequence.chords.map(\.id), ids)
    }

    func testEditingARepeatEditsThemAll() {
        var (sequence, id) = grouped()
        sequence.setRange(of: id, to: BeatRange(0, 16))
        // Change the C in the second time round
        let secondC = sequence.chords[5]
        XCTAssertEqual(secondC.symbol, "C")
        sequence.update(secondC.id, symbol: "Em")
        XCTAssertEqual(symbols(sequence), ["Am", "Em", "G", "F", "Am", "Em", "G", "F"])
        // A new chord at the playhead inside a repeat goes into the pattern
        sequence.setChord("Dm", in: BeatRange(14, 16))
        XCTAssertEqual(symbols(sequence), ["Am", "Em", "G", "Dm", "Am", "Em", "G", "Dm"])
        // Moving one moves it everywhere (within the pattern)
        var moved = sequence.chords[6]
        moved.range = BeatRange(12.5, 14)
        sequence.place(moved)
        XCTAssertEqual(sequence.chords.filter { $0.symbol == "G" }.map(\.range), [BeatRange(4.5, 6), BeatRange(12.5, 14)])
        // Clearing in one round clears in all
        sequence.clearChords(in: BeatRange(8, 10))
        XCTAssertEqual(symbols(sequence), ["Em", "G", "Dm", "Em", "G", "Dm"])
    }

    func testRemovingAPattern() {
        var (sequence, id) = grouped()
        let copy = sequence.duplicate(id)!
        sequence.setChord("E", in: BeatRange(16, 20))
        // Removing one copy leaves the other, and the pattern
        sequence.removeInstance(copy)
        XCTAssertEqual(symbols(sequence), ["Am", "C", "G", "F", "E"])
        XCTAssertEqual(sequence.patterns.count, 1)
        // Clearing a selection that takes in the whole pattern removes it (and the plain chords in it)
        sequence.clearChords(in: BeatRange(0, 18))
        XCTAssertTrue(sequence.instances.isEmpty)
        XCTAssertTrue(sequence.patterns.isEmpty)
        XCTAssertEqual(sequence.chords.map(\.range), [BeatRange(18, 20)])
    }

    func testDuplicatesAreLinkedUntilMadeUnique() {
        var (sequence, id) = grouped()
        sequence.setChord("Bb", in: BeatRange(8, 10))   // a plain chord where the copy goes
        let copy = sequence.duplicate(id)!
        XCTAssertEqual(sequence.instances.count, 2)
        XCTAssertEqual(sequence.patterns.count, 1)
        XCTAssertEqual(symbols(sequence), ["Am", "C", "G", "F", "Am", "C", "G", "F"])
        sequence.update(sequence.chords[0].id, symbol: "A7")
        XCTAssertEqual(sequence.chords[4].symbol, "A7")

        sequence.makeUnique(copy)
        XCTAssertEqual(sequence.patterns.count, 2)
        sequence.update(sequence.chords[4].id, symbol: "Dm")
        XCTAssertEqual(sequence.chords[0].symbol, "A7")
        XCTAssertEqual(sequence.chords[4].symbol, "Dm")
    }

    func testTrimmingTheStartStartsPartWay() {
        var (sequence, id) = grouped()
        sequence.setRange(of: id, to: BeatRange(4, 12))
        // Starts with the G (2 bars in), then round again
        XCTAssertEqual(symbols(sequence), ["G", "F", "Am", "C"])
        XCTAssertEqual(sequence.instances.first?.phase, 4)
    }

    func testUngroupingLeavesPlainChords() {
        var (sequence, id) = grouped()
        sequence.setRange(of: id, to: BeatRange(0, 12))
        sequence.ungroup(id)
        XCTAssertTrue(sequence.patterns.isEmpty)
        XCTAssertEqual(sequence.looseChords.map(\.symbol), ["Am", "C", "G", "F", "Am", "C"])
        // Now independent
        sequence.update(sequence.chords[0].id, symbol: "E7")
        XCTAssertEqual(sequence.chords[4].symbol, "Am")
    }

    func testFilesKeepPatternsAndOldSectionsBecomeThem() throws {
        var (sequence, id) = grouped()
        sequence.setRange(of: id, to: BeatRange(0, 16))
        let read = try JSONDecoder().decode(ChordSequence.self, from: sequence.encoded())
        XCTAssertEqual(read.chords.map(\.symbol), sequence.chords.map(\.symbol))
        XCTAssertEqual(read.instances, sequence.instances)

        let old = #"{"version": 1, "tempo": 100, "beatsPerBar": 4, "lengthInBars": 8, "chords": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "range": {"start": 0, "end": 4}, "symbol": "C"}, {"id": "7F9619FF-8B86-D011-B42D-00CF4FC964FF", "range": {"start": 4, "end": 8}, "symbol": "G"}], "sections": [{"id": "8F9619FF-8B86-D011-B42D-00CF4FC964FF", "name": "Intro", "range": {"start": 0, "end": 8}}]}"#
        let migrated = try JSONDecoder().decode(ChordSequence.self, from: Data(old.utf8))
        XCTAssertEqual(migrated.partName(at: 1), "Intro")
        XCTAssertEqual(migrated.chords.map(\.symbol), ["C", "G"])
        XCTAssertTrue(migrated.looseChords.isEmpty)
    }
}
