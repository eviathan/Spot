import XCTest
@testable import SpotCore

final class DiatonicChordTests: XCTestCase {
    private var library: LibraryBundle!

    override func setUpWithError() throws {
        library = try LibraryBundle.builtIn()
    }

    private func build(_ scaleId: String, size: Int) -> [DiatonicChord] {
        let scale = library.scales.first { $0.id == "builtin.scale." + scaleId }!
        return DiatonicChords.build(scale: scale.formula, size: size, chords: library.chords)
    }

    func testMajorTriads() {
        let chords = build("major", size: 3)
        XCTAssertEqual(chords.map(\.numeral), ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
        XCTAssertEqual(chords.map { $0.chord?.id }, [
            "major", "minor", "minor", "major", "major", "minor", "diminished",
        ].map { "builtin.chord." + $0 })
    }

    func testMajorSevenths() {
        let chords = build("major", size: 4)
        XCTAssertEqual(chords.map(\.numeral), ["Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "viiø7"])
        XCTAssertEqual(chords[6].chord?.id, "builtin.chord.half-diminished-7")
        XCTAssertEqual(chords[1].formula.description, "1 b3 5 b7")
        XCTAssertEqual(chords[1].scaleDegrees.map(\.description), ["2", "4", "6", "1"])
    }

    func testMinorKeysUseFlatNumerals() {
        XCTAssertEqual(build("natural-minor", size: 3).map(\.numeral), ["i", "ii°", "♭III", "iv", "v", "♭VI", "♭VII"])
    }

    func testHarmonicMinorSevenths() {
        let chords = build("harmonic-minor", size: 4)
        XCTAssertEqual(chords.map(\.numeral), ["i(maj7)", "iiø7", "♭III+maj7", "iv7", "V7", "♭VImaj7", "vii°7"])
        XCTAssertEqual(chords[2].chord?.id, "builtin.chord.augmented-major-7")
        XCTAssertEqual(chords[6].chord?.id, "builtin.chord.diminished-7")
        XCTAssertTrue(chords.allSatisfy { $0.chord != nil })
    }

    /// Scales in the "Other" family stack into unnamed triads such as 1 bb3 b5, so they're left out.
    func testEveryHeptatonicScaleMatchesLibraryChords() {
        for scale in library.scales where scale.formula.degrees.count == 7 && scale.family != "Other" {
            let triads = DiatonicChords.build(scale: scale.formula, size: 3, chords: library.chords)
            XCTAssertEqual(triads.count, 7, scale.id)
            XCTAssertTrue(triads.allSatisfy { $0.chord != nil }, "\(scale.id): \(triads.filter { $0.chord == nil }.map(\.formula))")
        }
    }

    func testOnlyForSevenNoteScales() {
        XCTAssertEqual(build("minor-pentatonic", size: 3), [])
        XCTAssertEqual(build("major", size: 5), [])
    }
}
