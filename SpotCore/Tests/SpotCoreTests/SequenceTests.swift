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
        sequence.backing = .comp

        let decoded = try JSONDecoder().decode(ChordSequence.self, from: sequence.encoded())
        XCTAssertEqual(decoded, sequence)

        let newer = #"{"version": 99, "tempo": 100, "beatsPerBar": 4, "lengthInBars": 4}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ChordSequence.self, from: Data(newer.utf8)))
    }
}

final class BackingTests: XCTestCase {
    private var parser: ChordSymbolParser!

    override func setUpWithError() throws {
        parser = ChordSymbolParser(chords: try LibraryBundle.builtIn().chords)
    }

    func testVoicingLayout() {
        let cmaj7 = Backing.voicing(for: parser.parse("Cmaj7")!)
        XCTAssertEqual(cmaj7.bass, 36)                                   // C2
        XCTAssertEqual(Set(cmaj7.upper.map { $0 % 12 }), [4, 7, 11])     // E G B above the bass
        XCTAssertTrue(cmaj7.upper.allSatisfy { (52...76).contains($0) })
        XCTAssertEqual(cmaj7.upper, cmaj7.upper.sorted())
        XCTAssertLessThan(cmaj7.upper.last! - cmaj7.upper.first!, 12)   // close position

        // Triads keep the root in the upper voices; slash chords change the bass
        XCTAssertEqual(Set(Backing.voicing(for: parser.parse("G")!).upper.map { $0 % 12 }), [7, 11, 2])
        XCTAssertEqual(Backing.voicing(for: parser.parse("C/E")!).bass, 40)
        // Big chords are thinned to four upper notes, keeping the required ones
        let thirteen = Backing.voicing(for: parser.parse("G13")!)
        XCTAssertEqual(thirteen.upper.count, 4)
        XCTAssertTrue(Set(thirteen.upper.map { $0 % 12 }).isSuperset(of: [11, 5]))   // B and F
    }

    func testVoiceLeadingMovesLittle() {
        var previous: [Int]?
        var moves: [Int] = []
        for symbol in ["Dm7", "G7", "Cmaj7"] {
            let voicing = Backing.voicing(for: parser.parse(symbol)!, previous: previous)
            if let previous {
                moves.append(zip(previous, voicing.upper).map { abs($0 - $1) }.reduce(0, +))
            }
            previous = voicing.upper
        }
        // ii-V-I voice leading: each voice moves a step or stays
        XCTAssertTrue(moves.allSatisfy { $0 <= 4 }, "\(moves)")
    }

    private func sequence(_ style: BackingStyle) -> (ChordSequence, [UUID: ChordSymbol]) {
        var sequence = ChordSequence(lengthInBars: 4)
        sequence.backing = style
        sequence.setChord("Dm7", in: sequence.bar(0))
        sequence.setChord("G7", in: sequence.bar(1))
        sequence.setChord("Cmaj7", in: BeatRange(8, 16))
        sequence.setChord("Nonsense", in: BeatRange(16, 16))
        let chords = Dictionary(uniqueKeysWithValues: sequence.chords.compactMap { region in
            parser.parse(region.symbol).map { (region.id, $0) }
        })
        return (sequence, chords)
    }

    func testPad() {
        let (sequence, chords) = self.sequence(.pad)
        let notes = Backing.notes(for: sequence, chords: chords)
        // Dm7: bass + 3 upper; G7: bass + 3; Cmaj7 (two bars): 2 bass + 3 upper
        XCTAssertEqual(notes.count, 4 + 4 + 5)
        XCTAssertTrue(notes.allSatisfy { $0.end > $0.start && $0.end < 16 })
        XCTAssertEqual(notes.filter { $0.start == 8 }.count, 4)
        XCTAssertEqual(notes.filter { $0.note < 48 }.map(\.start), [0, 4, 8, 12])
    }

    func testStrumAndComp() {
        let (strumSequence, chords) = self.sequence(.strum)
        let strums = Backing.notes(for: strumSequence, chords: chords).filter { $0.note >= 48 }
        // 16 beats, 3 upper notes each, slightly staggered
        XCTAssertEqual(strums.count, 48)
        XCTAssertEqual(Set(strums.filter { $0.start < 1 }.map(\.start)).count, 3)

        var compSequence = strumSequence
        compSequence.backing = .comp
        let stabs = Backing.notes(for: compSequence, chords: chords).filter { $0.note >= 48 }
        XCTAssertEqual(Set(stabs.map(\.start)), [0, 1.5, 4, 5.5, 8, 9.5, 12, 13.5])

        compSequence.backing = .off
        XCTAssertEqual(Backing.notes(for: compSequence, chords: chords), [])
    }
}
