import XCTest
@testable import SpotCore

final class IntervalNameTests: XCTestCase {
    func testNames() {
        let cases: [(String, String)] = [
            ("1", "R"), ("b2", "m2"), ("2", "M2"), ("#2", "A2"), ("b3", "m3"), ("3", "M3"), ("b4", "d4"),
            ("4", "P4"), ("#4", "A4"), ("b5", "d5"), ("5", "P5"), ("#5", "A5"), ("b6", "m6"), ("6", "M6"),
            ("bb7", "d7"), ("b7", "m7"), ("7", "M7"), ("b9", "m9"), ("9", "M9"), ("#9", "A9"),
            ("11", "P11"), ("#11", "A11"), ("b13", "m13"), ("13", "M13"),
        ]
        for (degree, name) in cases {
            XCTAssertEqual(Degree(degree)?.intervalName, name, degree)
        }
        XCTAssertEqual(Degree.chromaticIntervalName(6), "TT")
        XCTAssertEqual(Degree.chromaticIntervalName(13), "m2")
    }
}

final class TuningTests: XCTestCase {
    func testNoteNames() {
        XCTAssertEqual(Tuning.noteName(midi: 40), "E2")
        XCTAssertEqual(Tuning.noteName(midi: 60), "C4")
        XCTAssertEqual(Tuning.midiNote(named: "E2"), 40)
        XCTAssertEqual(Tuning.midiNote(named: "Bb1"), 34)
        XCTAssertEqual(Tuning.midiNote(named: "B#3"), 60)
        XCTAssertEqual(Tuning.midiNote(named: "Cb4"), 59)
        XCTAssertNil(Tuning.midiNote(named: "E"))
    }

    func testCodableUsesNoteNames() throws {
        let data = try JSONEncoder().encode(Tuning.dropD)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#"["D2","A2","D3","G3","B3","E4"]"#))
        XCTAssertEqual(try JSONDecoder().decode(Tuning.self, from: data), .dropD)
    }
}

final class FretboardTests: XCTestCase {
    func testPitches() {
        let fretboard = Fretboard()
        XCTAssertEqual(fretboard.allPositions.count, 6 * 25)
        XCTAssertEqual(fretboard.pitchClass(at: FretPosition(string: 0, fret: 5)), PitchClass(9))   // A
        XCTAssertEqual(fretboard.midiNote(at: FretPosition(string: 5, fret: 12)), 76)              // E5
        XCTAssertEqual(fretboard.positions(of: PitchClass(4)).count, 14)                           // every E
    }

    func testMarkers() throws {
        let fretboard = Fretboard()
        let root = SpelledNote("D")!
        let markers = FretMarker.build(fretboard: fretboard, root: root, formula: Formula("1 2 3 4 5 6 7")!,
                                       key: Key(root, .major), shape: nil)

        XCTAssertEqual(markers.count, fretboard.allPositions.count)

        // Low E string, 2nd fret: F#, the major 3rd of D
        let fSharp = try XCTUnwrap(markers.first { $0.position == FretPosition(string: 0, fret: 2) })
        XCTAssertEqual(fSharp.noteName.asciiDescription, "F#")
        XCTAssertEqual(fSharp.intervalName, "M3")
        XCTAssertEqual(fSharp.semitonesAboveRoot, 4)
        XCTAssertTrue(fSharp.isInCollection)
        XCTAssertTrue(fSharp.isInPosition)

        // Low E string, 1st fret: F natural, outside D major
        let f = try XCTUnwrap(markers.first { $0.position == FretPosition(string: 0, fret: 1) })
        XCTAssertEqual(f.noteName.asciiDescription, "F")
        XCTAssertEqual(f.intervalName, "m3")
        XCTAssertFalse(f.isInCollection)
    }

    func testChordMarkersUseCompoundDegrees() throws {
        let root = SpelledNote("C")!
        let markers = FretMarker.build(fretboard: Fretboard(), root: root, formula: Formula("1 3 5 b7 #9")!,
                                       key: Key(root, .major), shape: [:])

        // Low E string, 3rd fret: G, the 5th;
        // A string, 6th fret: D#, the #9 (spelled from the chord, not the key)
        let sharpNine = try XCTUnwrap(markers.first { $0.position == FretPosition(string: 1, fret: 6) })
        XCTAssertEqual(sharpNine.noteName.asciiDescription, "D#")
        XCTAssertEqual(sharpNine.intervalName, "A9")
        XCTAssertFalse(sharpNine.isInPosition)
    }
}
