import XCTest
@testable import SpotCore

final class DegreeTests: XCTestCase {
    func testParsingAndSemitones() {
        let cases: [(String, Int)] = [
            ("1", 0), ("b2", 1), ("2", 2), ("#2", 3), ("b3", 3), ("3", 4), ("b4", 4), ("4", 5),
            ("#4", 6), ("b5", 6), ("5", 7), ("#5", 8), ("b6", 8), ("6", 9), ("bb7", 9), ("b7", 10),
            ("7", 11), ("b9", 13), ("9", 14), ("#9", 15), ("11", 17), ("#11", 18), ("b13", 20), ("13", 21),
        ]

        for (text, semitones) in cases {
            let degree = Degree(text)
            XCTAssertNotNil(degree, text)
            XCTAssertEqual(degree?.semitones, semitones, text)
            XCTAssertEqual(degree?.description, text)
        }
    }

    func testUnicodeAccidentals() {
        XCTAssertEqual(Degree("♭9"), Degree("b9"))
        XCTAssertEqual(Degree("♯11"), Degree("#11"))
        XCTAssertEqual(Degree("b9")?.prettyDescription, "♭9")
    }

    func testInvalid() {
        XCTAssertNil(Degree(""))
        XCTAssertNil(Degree("b"))
        XCTAssertNil(Degree("0"))
        XCTAssertNil(Degree("x3"))
        XCTAssertNil(Formula("1 b3 q"))
    }
}

final class SpellingTests: XCTestCase {
    private func names(_ notes: [SpelledNote]) -> String {
        notes.map(\.asciiDescription).joined(separator: " ")
    }

    func testAllMajorKeys() {
        let expected = [
            "C D E F G A B",
            "Db Eb F Gb Ab Bb C",
            "D E F# G A B C#",
            "Eb F G Ab Bb C D",
            "E F# G# A B C# D#",
            "F G A Bb C D E",
            "F# G# A# B C# D# E#",
            "G A B C D E F#",
            "Ab Bb C Db Eb F G",
            "A B C# D E F# G#",
            "Bb C D Eb F G A",
            "B C# D# E F# G# A#",
        ]

        for pitchClass in 0..<12 {
            let key = Key(conventional: PitchClass(pitchClass), .major)
            XCTAssertEqual(names(key.scale), expected[pitchClass], key.description)
        }
    }

    func testAllMinorKeys() {
        let expected = [
            "C D Eb F G Ab Bb",
            "C# D# E F# G# A B",
            "D E F G A Bb C",
            "Eb F Gb Ab Bb Cb Db",
            "E F# G A B C D",
            "F G Ab Bb C Db Eb",
            "F# G# A B C# D E",
            "G A Bb C D Eb F",
            "G# A# B C# D# E F#",
            "A B C D E F G",
            "Bb C Db Eb F Gb Ab",
            "B C# D E F# G A",
        ]

        for pitchClass in 0..<12 {
            let key = Key(conventional: PitchClass(pitchClass), .minor)
            XCTAssertEqual(names(key.scale), expected[pitchClass], key.description)
        }
    }

    func testTheoreticalKeysUseDoubleAccidentals() {
        XCTAssertEqual(names(Key(SpelledNote("G#")!, .major).scale), "G# A# B# C# D# E# Fx")
        XCTAssertEqual(names(Key(SpelledNote("Fb")!, .major).scale), "Fb Gb Ab Bbb Cb Db Eb")
        XCTAssertEqual(SpelledNote("Fx")?.description, "F𝄪")
    }

    func testChordSpelling() {
        XCTAssertEqual(names(Formula("1 3 5 b7")!.spelled(from: SpelledNote("Bb")!)), "Bb D F Ab")
        XCTAssertEqual(names(Formula("1 b3 b5 bb7")!.spelled(from: SpelledNote("C")!)), "C Eb Gb Bbb")
        XCTAssertEqual(names(Formula("1 3 5 b7 #9")!.spelled(from: SpelledNote("E")!)), "E G# B D Fx")
        XCTAssertEqual(names(Formula("1 3 5 7 #11")!.spelled(from: SpelledNote("F")!)), "F A C E B")
    }

    func testChromaticSpellingInKey() {
        let cMajor = Key(SpelledNote("C")!, .major)
        XCTAssertEqual(names((0..<12).map { cMajor.spell(PitchClass($0)) }), "C Db D Eb E F F# G Ab A Bb B")

        let aMinor = Key(SpelledNote("A")!, .minor)
        XCTAssertEqual(names((0..<12).map { aMinor.spell(PitchClass($0 + 9)) }), "A Bb B C C# D D# E F F# G G#")

        let dMajor = Key(SpelledNote("D")!, .major)
        XCTAssertEqual(dMajor.spell(PitchClass(5)).asciiDescription, "F")
        XCTAssertEqual(dMajor.spell(PitchClass(6)).asciiDescription, "F#")
    }

    func testModeRotation() {
        let major = Formula("1 2 3 4 5 6 7")!
        XCTAssertEqual(major.modePitchClassOffsets(startingAt: 2), Formula("1 2 b3 4 5 6 b7")!.pitchClassOffsets)
        XCTAssertEqual(major.modePitchClassOffsets(startingAt: 7), Formula("1 b2 b3 4 b5 b6 b7")!.pitchClassOffsets)
    }

    /// Modes take their relative major's key signature, and name themselves.
    func testModalKeys() {
        let cases: [(Int, KeyQuality, String)] = [
            (11, .dorian, "B C# D E F# G# A"),
            (1, .phrygian, "C# D E F# G# A B"),
            (3, .lydian, "Eb F G A Bb C D"),
            (6, .mixolydian, "F# G# A# B C# D# E"),
            (11, .locrian, "B C D E F G A"),
            (2, .dorian, "D E F G A B C"),
        ]
        for (pitchClass, quality, expected) in cases {
            let key = Key(conventional: PitchClass(pitchClass), quality)
            XCTAssertEqual(names(key.scale), expected, key.description)
        }
        let dorian = Key(conventional: PitchClass(2), .dorian)
        XCTAssertEqual(dorian.description, "D Dorian")
        XCTAssertEqual(dorian.shortName, "D dor")
        XCTAssertEqual(Key(conventional: PitchClass(9), .minor).shortName, "Am")
        // Outside the mode: the nearest common alteration
        XCTAssertEqual(dorian.spell(PitchClass(10)).asciiDescription, "Bb")
        XCTAssertEqual(dorian.spell(PitchClass(6)).asciiDescription, "F#")
        XCTAssertEqual(KeyQuality(scaleId: "builtin.scale.mixolydian"), .mixolydian)
        XCTAssertEqual(KeyQuality(scaleId: "builtin.scale.natural-minor"), .minor)
        XCTAssertTrue(KeyQuality.phrygian.isMinor)
        XCTAssertFalse(KeyQuality.lydian.isMinor)
    }
}
