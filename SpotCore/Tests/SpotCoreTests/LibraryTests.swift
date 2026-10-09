import XCTest
@testable import SpotCore

final class BuiltInLibraryTests: XCTestCase {
    private var library: LibraryBundle!

    override func setUpWithError() throws {
        library = try LibraryBundle.builtIn()
    }

    func testIsValid() {
        XCTAssertEqual(library.validate(), [])
    }

    /// Pitch sets written as semitones, independently of the degree spellings in the JSON.
    /// Entries marked "tonal" were taken from tonal's dictionaries (see Scripts/check_library.py).
    func testScalePitchSets() {
        let reference: [String: [Int]] = [
            "major": [0, 2, 4, 5, 7, 9, 11],
            "dorian": [0, 2, 3, 5, 7, 9, 10],
            "phrygian": [0, 1, 3, 5, 7, 8, 10],
            "lydian": [0, 2, 4, 6, 7, 9, 11],
            "mixolydian": [0, 2, 4, 5, 7, 9, 10],
            "natural-minor": [0, 2, 3, 5, 7, 8, 10],
            "locrian": [0, 1, 3, 5, 6, 8, 10],
            "harmonic-minor": [0, 2, 3, 5, 7, 8, 11],
            "locrian-natural-6": [0, 1, 3, 5, 6, 9, 10],
            "ionian-sharp-5": [0, 2, 4, 5, 8, 9, 11],
            "dorian-sharp-4": [0, 2, 3, 6, 7, 9, 10],
            "phrygian-dominant": [0, 1, 4, 5, 7, 8, 10],
            "lydian-sharp-2": [0, 3, 4, 6, 7, 9, 11],
            "super-locrian-bb7": [0, 1, 3, 4, 6, 8, 9],
            "melodic-minor": [0, 2, 3, 5, 7, 9, 11],
            "dorian-b2": [0, 1, 3, 5, 7, 9, 10],
            "lydian-augmented": [0, 2, 4, 6, 8, 9, 11],
            "lydian-dominant": [0, 2, 4, 6, 7, 9, 10],
            "mixolydian-b6": [0, 2, 4, 5, 7, 8, 10],
            "aeolian-b5": [0, 2, 3, 5, 6, 8, 10],
            "altered": [0, 1, 3, 4, 6, 8, 10],
            "major-pentatonic": [0, 2, 4, 7, 9],
            "minor-pentatonic": [0, 3, 5, 7, 10],
            "blues": [0, 3, 5, 6, 7, 10],
            "chromatic": Array(0..<12),
            "harmonic-major": [0, 2, 4, 5, 7, 8, 11],  // tonal
            "dorian-b5": [0, 2, 3, 5, 6, 9, 10],  // spot (checked by mode rotation)
            "phrygian-b4": [0, 1, 3, 4, 7, 8, 10],  // spot (checked by mode rotation)
            "lydian-b3": [0, 2, 3, 6, 7, 9, 11],  // tonal
            "mixolydian-b2": [0, 1, 4, 5, 7, 9, 10],  // spot (checked by mode rotation)
            "lydian-augmented-sharp-2": [0, 3, 4, 6, 8, 9, 11],  // spot (checked by mode rotation)
            "locrian-bb7": [0, 1, 3, 5, 6, 8, 9],  // spot (checked by mode rotation)
            "egyptian": [0, 2, 5, 7, 10],  // tonal
            "man-gong": [0, 3, 5, 8, 10],  // tonal
            "ritusen": [0, 2, 5, 7, 9],  // tonal
            "in-sen": [0, 1, 5, 7, 10],  // tonal
            "hirajoshi": [0, 2, 3, 7, 8],  // tonal
            "iwato": [0, 1, 5, 6, 10],  // tonal
            "kumoi": [0, 2, 3, 7, 9],  // tonal
            "major-blues": [0, 2, 3, 4, 7, 9],  // tonal
            "bebop-dominant": [0, 2, 4, 5, 7, 9, 10, 11],  // tonal
            "bebop-major": [0, 2, 4, 5, 7, 8, 9, 11],  // tonal
            "bebop-dorian": [0, 2, 3, 4, 5, 7, 9, 10],  // tonal
            "bebop-melodic-minor": [0, 2, 3, 5, 7, 8, 9, 11],  // tonal
            "bebop-natural-minor": [0, 2, 3, 5, 7, 8, 10, 11],  // tonal
            "whole-tone": [0, 2, 4, 6, 8, 10],  // tonal
            "half-whole-diminished": [0, 1, 3, 4, 6, 7, 9, 10],  // tonal
            "whole-half-diminished": [0, 2, 3, 5, 6, 8, 9, 11],  // tonal
            "hungarian-minor": [0, 2, 3, 6, 7, 8, 11],  // tonal
            "hungarian-major": [0, 3, 4, 6, 7, 9, 10],  // tonal
            "double-harmonic-major": [0, 1, 4, 5, 7, 8, 11],  // tonal
            "neapolitan-major": [0, 1, 3, 5, 7, 9, 11],  // tonal
            "neapolitan-minor": [0, 1, 3, 5, 7, 8, 11],  // spot (checked by mode rotation)
            "persian": [0, 1, 4, 5, 6, 8, 11],  // tonal
            "enigmatic": [0, 1, 4, 6, 8, 10, 11],  // tonal
            "prometheus": [0, 2, 4, 6, 9, 10],  // tonal
            "locrian-major": [0, 2, 4, 5, 6, 8, 10],  // tonal
            "augmented": [0, 3, 4, 7, 8, 11],  // tonal
        ]

        XCTAssertEqual(Set(library.scales.map(\.id)), Set(reference.keys.map { "builtin.scale." + $0 }))
        for scale in library.scales {
            let key = String(scale.id.dropFirst("builtin.scale.".count))
            XCTAssertEqual(scale.formula.pitchClassOffsets, Set(reference[key] ?? []), scale.id)
        }
    }

    /// Chord tones as semitones above the root (compound intervals kept above 12).
    func testChordSemitones() {
        let reference: [String: [Int]] = [
            "major": [0, 4, 7],
            "add4": [0, 4, 5, 7],
            "major-6": [0, 4, 7, 9],
            "six-nine": [0, 4, 7, 9, 14],
            "major-7": [0, 4, 7, 11],
            "major-9": [0, 4, 7, 11, 14],
            "major-11": [0, 4, 7, 11, 14, 17],
            "major-13": [0, 4, 7, 11, 14, 17, 21],
            "major-7-sharp-11": [0, 4, 7, 11, 18],
            "major-flat-5": [0, 4, 6],
            "minor": [0, 3, 7],
            "minor-add4": [0, 3, 5, 7],
            "minor-6": [0, 3, 7, 9],
            "minor-7": [0, 3, 7, 10],
            "minor-add9": [0, 3, 7, 14],
            "minor-six-nine": [0, 3, 7, 9, 14],
            "minor-9": [0, 3, 7, 10, 14],
            "minor-11": [0, 3, 7, 10, 14, 17],
            "minor-13": [0, 3, 7, 10, 14, 17, 21],
            "minor-major-7": [0, 3, 7, 11],
            "minor-major-9": [0, 3, 7, 11, 14],
            "minor-major-11": [0, 3, 7, 11, 14, 17],
            "minor-major-13": [0, 3, 7, 11, 14, 17, 21],
            "half-diminished-7": [0, 3, 6, 10],
            "dominant-7": [0, 4, 7, 10],
            "dominant-9": [0, 4, 7, 10, 14],
            "dominant-11": [0, 4, 7, 10, 14, 17],
            "dominant-13": [0, 4, 7, 10, 14, 17, 21],
            "dominant-7-sharp-5": [0, 4, 8, 10],
            "dominant-7-flat-5": [0, 4, 6, 10],
            "dominant-7-sharp-9": [0, 4, 7, 10, 15],
            "dominant-7-flat-9": [0, 4, 7, 10, 13],
            "dominant-9-sharp-5": [0, 4, 8, 10, 14],
            "dominant-9-flat-5": [0, 4, 6, 10, 14],
            "dominant-7-sharp-5-sharp-9": [0, 4, 8, 10, 15],
            "dominant-7-sharp-5-flat-9": [0, 4, 8, 10, 13],
            "dominant-7-flat-5-sharp-9": [0, 4, 6, 10, 15],
            "dominant-7-flat-5-flat-9": [0, 4, 6, 10, 13],
            "dominant-7-sharp-11": [0, 4, 7, 10, 18],
            "augmented": [0, 4, 8],
            "augmented-major-7": [0, 4, 8, 11],
            "diminished": [0, 3, 6],
            "diminished-7": [0, 3, 6, 9],
            "power": [0, 7],
            "flat-5-dyad": [0, 6],
            "sus4": [0, 5, 7],
            "sus2": [0, 2, 7],
            "sharp-11-no-3": [0, 7, 18],
            "add9": [0, 4, 7, 14],  // tonal
            "major-9-sharp-11": [0, 4, 7, 11, 14, 18],  // tonal
            "major-9-sharp-5": [0, 4, 8, 11, 14],  // tonal
            "major-7-flat-5": [0, 4, 6, 11],  // tonal
            "minor-7-sharp-5": [0, 3, 8, 10],  // tonal
            "dominant-9-sharp-11": [0, 4, 7, 10, 14, 18],  // tonal
            "dominant-13-flat-9": [0, 4, 7, 10, 13, 21],  // tonal
            "dominant-13-sharp-11": [0, 4, 7, 10, 14, 18, 21],  // tonal
            "dominant-7-flat-13": [0, 4, 7, 10, 20],  // tonal
            "dominant-7-flat-9-flat-13": [0, 4, 7, 10, 13, 20],  // tonal
            "dominant-7-sharp-9-flat-13": [0, 4, 7, 10, 15, 20],  // tonal
            "dominant-7-sus4": [0, 5, 7, 10],  // tonal
            "dominant-9-sus4": [0, 5, 7, 10, 14],  // tonal
            "dominant-13-sus4": [0, 5, 7, 10, 14, 21],  // tonal
            "diminished-major-7": [0, 3, 6, 11],  // tonal
            "quartal": [0, 5, 10, 15],  // tonal
        ]

        XCTAssertEqual(Set(library.chords.map(\.id)), Set(reference.keys.map { "builtin.chord." + $0 }))
        for chord in library.chords {
            let key = String(chord.id.dropFirst("builtin.chord.".count))
            XCTAssertEqual(chord.formula.degrees.map(\.semitones), reference[key] ?? [], chord.id)
        }
    }

    func testValidationCatchesProblems() {
        var broken = library!
        broken.scales[1].formula = Formula("1 2 3 4 5 6 b7")!   // no longer mode 2 of major
        broken.chords.append(ChordDefinition(id: "x", name: "x", symbols: ["m7"], formula: Formula("1 5 3")!))

        let issues = broken.validate()
        XCTAssertTrue(issues.contains { $0.contains("not mode 2") })
        XCTAssertTrue(issues.contains { $0.contains("\"m7\"") })
        XCTAssertTrue(issues.contains { $0.contains("ascending") })
    }
}

final class LibraryBundleTests: XCTestCase {
    func testRoundTrip() throws {
        let library = try LibraryBundle.builtIn()
        let decoded = try LibraryBundle.decode(from: library.encoded())
        XCTAssertEqual(decoded, library)
    }

    func testMinimalFileUsesDefaults() throws {
        let json = """
        {
          "format": "spot.library", "version": 1,
          "bundle": { "id": "test", "name": "Test" },
          "scales": [ { "id": "s", "name": "S", "formula": "1 2 b3" } ],
          "chords": [ { "id": "c", "name": "C", "symbols": ["x"], "formula": "1 b3 5", "optional": ["5"] } ]
        }
        """
        let bundle = try LibraryBundle.decode(from: Data(json.utf8))
        XCTAssertEqual(bundle.scales.first?.aliases, [])
        XCTAssertEqual(bundle.chords.first?.requiredDegrees, [Degree(1), Degree("b3")!])
    }

    func testRejectsNewerVersionAndOtherFormats() {
        let newer = Data(#"{"format": "spot.library", "version": 99}"#.utf8)
        XCTAssertThrowsError(try LibraryBundle.decode(from: newer)) { error in
            XCTAssertEqual(error as? LibraryBundleError, .unsupportedVersion(99))
        }

        let other = Data(#"{"format": "something.else", "version": 1}"#.utf8)
        XCTAssertThrowsError(try LibraryBundle.decode(from: other)) { error in
            XCTAssertEqual(error as? LibraryBundleError, .unsupportedFormat("something.else"))
        }
    }

    func testRejectsBadFormula() {
        let json = """
        { "format": "spot.library", "version": 1, "bundle": { "id": "t", "name": "T" },
          "scales": [ { "id": "s", "name": "S", "formula": "1 q 3" } ], "chords": [] }
        """
        XCTAssertThrowsError(try LibraryBundle.decode(from: Data(json.utf8)))
    }
}

final class ChordSymbolParserTests: XCTestCase {
    private var parser: ChordSymbolParser!

    override func setUpWithError() throws {
        parser = ChordSymbolParser(chords: try LibraryBundle.builtIn().chords)
    }

    private func check(_ text: String, root: String, chord: String, bass: String? = nil,
                       file: StaticString = #filePath, line: UInt = #line) {
        guard let symbol = parser.parse(text) else {
            return XCTFail("Could not parse \(text)", file: file, line: line)
        }
        XCTAssertEqual(symbol.root.asciiDescription, root, text, file: file, line: line)
        XCTAssertEqual(symbol.chord.id, "builtin.chord." + chord, text, file: file, line: line)
        XCTAssertEqual(symbol.bass?.asciiDescription, bass, text, file: file, line: line)
    }

    func testCommonSymbols() {
        check("C", root: "C", chord: "major")
        check("Cm7", root: "C", chord: "minor-7")
        check("Ebmaj7", root: "Eb", chord: "major-7")
        check("E♭Δ7", root: "Eb", chord: "major-7")
        check("F#m7b5", root: "F#", chord: "half-diminished-7")
        check("Bø", root: "B", chord: "half-diminished-7")
        check("G7", root: "G", chord: "dominant-7")
        check("Bdim7", root: "B", chord: "diminished-7")
        check(" Asus4 ", root: "A", chord: "sus4")
    }

    func testSlashChords() {
        check("Bb7#9/D", root: "Bb", chord: "dominant-7-sharp-9", bass: "D")
        check("C/E", root: "C", chord: "major", bass: "E")
        check("Am7/G", root: "A", chord: "minor-7", bass: "G")
    }

    func testSymbolsContainingSlash() {
        check("C6/9", root: "C", chord: "six-nine")
        check("Cm/Maj7", root: "C", chord: "minor-major-7")
        check("Cm6/9/Eb", root: "C", chord: "minor-six-nine", bass: "Eb")
    }

    func testAmbiguousRootAccidental() {
        // Longest root reading wins: Cb5 is a C♭ power chord, C#11 is C♯ eleventh
        check("Cb5", root: "Cb", chord: "power")
        check("C#11", root: "C#", chord: "dominant-11")
        // ...but fall back to a shorter root when that's the only valid reading
        check("CMajb5", root: "C", chord: "major-flat-5")
        check("Cb9", root: "Cb", chord: "dominant-9")
        check("C7b9", root: "C", chord: "dominant-7-flat-9")
    }

    func testInvalid() {
        XCTAssertNil(parser.parse(""))
        XCTAssertNil(parser.parse("H7"))
        XCTAssertNil(parser.parse("Cxyz"))
        XCTAssertNil(parser.parse("C/H"))
    }

    func testDescriptionRoundTrip() throws {
        let symbol = try XCTUnwrap(parser.parse("Bb7#9/D"))
        XCTAssertEqual(symbol.description, "B♭7#9/D")
        XCTAssertEqual(symbol.asciiDescription, "Bb7#9/D")
        XCTAssertEqual(parser.parse(symbol.asciiDescription), symbol)
        XCTAssertEqual(symbol.tones.map(\.asciiDescription), ["Bb", "D", "F", "Ab", "C#"])
    }
}
