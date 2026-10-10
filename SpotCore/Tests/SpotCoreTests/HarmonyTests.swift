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

final class ChordScaleMatcherTests: XCTestCase {
    private var library: LibraryBundle!
    private var parser: ChordSymbolParser!

    override func setUpWithError() throws {
        library = try LibraryBundle.builtIn()
        parser = ChordSymbolParser(chords: library.chords)
    }

    private func chord(_ id: String) -> ChordDefinition {
        library.chords.first { $0.id == "builtin.chord." + id }!
    }

    private func scale(_ id: String) -> ScaleDefinition {
        library.scales.first { $0.id == "builtin.scale." + id }!
    }

    private func ids(_ suggestions: [ScaleSuggestion]) -> [String] {
        suggestions.map { $0.scale.id.replacingOccurrences(of: "builtin.scale.", with: "") }
    }

    func testDm7InCMajorPrefersDorian() {
        let key = Key(SpelledNote("C")!, .major)
        let suggestions = ChordScaleMatcher.scales(for: chord("minor-7"), root: PitchClass(2), among: library.scales,
                                                   context: ChordContext(key: key))
        XCTAssertEqual(ids(suggestions).first, "dorian")
        XCTAssertTrue(suggestions[0].reasons.contains("Fits C major"))
        XCTAssertTrue(suggestions[0].avoidNotes.isEmpty)
        // Every suggestion contains the chord
        XCTAssertFalse(ids(suggestions).contains("major"))
    }

    func testG7InCMajorPrefersMixolydianWithAvoid11() {
        let key = Key(SpelledNote("C")!, .major)
        let suggestions = ChordScaleMatcher.scales(for: chord("dominant-7"), root: PitchClass(7), among: library.scales,
                                                   context: ChordContext(key: key))
        XCTAssertEqual(ids(suggestions).first, "mixolydian")
        XCTAssertEqual(suggestions[0].avoidNotes.map(\.description), ["11"])
        XCTAssertTrue(ids(suggestions).contains("altered"))
        XCTAssertTrue(ids(suggestions).contains("lydian-dominant"))
    }

    func testAlteredDominantWithoutKey() {
        let suggestions = ChordScaleMatcher.scales(for: chord("dominant-7-sharp-9"), root: PitchClass(7), among: library.scales)
        // 7#9 rules out Mixolydian; the altered and half-whole scales fit
        XCTAssertFalse(ids(suggestions).contains("mixolydian"))
        XCTAssertTrue(ids(suggestions).prefix(3).contains("altered"))
        XCTAssertTrue(ids(suggestions).contains("half-whole-diminished"))
    }

    func testRoles() {
        // Ionian over maj7: the 4 is the avoid note, 9 and 13 are tensions
        let ionian = ChordScaleMatcher.roles(chord: chord("major-7"), scale: scale("major"))
        XCTAssertEqual(ionian[5], .avoid)
        XCTAssertEqual(ionian[2], .tension)
        XCTAssertEqual(ionian[9], .tension)
        XCTAssertEqual(ionian[11], .chordTone)
        XCTAssertEqual(ionian[6], .outside)

        // Lydian has no avoid notes over maj7
        XCTAssertFalse(ChordScaleMatcher.roles(chord: chord("major-7"), scale: scale("lydian")).values.contains(.avoid))

        // b9 is a tension over a dominant chord, but an avoid note over minor
        XCTAssertEqual(ChordScaleMatcher.roles(chord: chord("dominant-7"), scale: scale("phrygian-dominant"))[1], .tension)
        XCTAssertEqual(ChordScaleMatcher.roles(chord: chord("minor-7"), scale: scale("phrygian"))[1], .avoid)

        // The altered scale has no 5th, so b13 doesn't clash with it
        XCTAssertEqual(ChordScaleMatcher.roles(chord: chord("dominant-7"), scale: scale("altered"))[8], .tension)
    }

    func testPreviousScaleFavoursSmoothChanges() {
        // After C major over Cmaj7, A natural minor (same notes) beats A dorian over Am7
        let previous = (scale: scale("major"), root: PitchClass(0))
        let suggestions = ChordScaleMatcher.scales(for: chord("minor-7"), root: PitchClass(9), among: library.scales,
                                                   context: ChordContext(previous: previous))
        XCTAssertEqual(ids(suggestions).first, "natural-minor")
        XCTAssertTrue(suggestions[0].reasons.contains("Same notes as the last chord"))
    }

    func testArpeggios() {
        let arpeggios = ChordScaleMatcher.arpeggios(for: chord("major-7"), scale: scale("lydian"), chords: library.chords)
        XCTAssertEqual(arpeggios[0].kind, .chord)
        XCTAssertEqual(arpeggios[1].kind, .guideTones)
        XCTAssertEqual(arpeggios[1].degreesOverChord.map(\.description), ["3", "7"])

        // Over Cmaj7 with Lydian: Em7 (3 5 7 9) and Bm7 (7 9 #11 13) are upper structures
        let upper = arpeggios.filter { $0.kind == .upperStructure }
        let labels = upper.map { $0.degreesOverChord.map(\.description).joined(separator: " ") }
        XCTAssertTrue(labels.contains("3 5 7 9"), "\(labels)")
        XCTAssertTrue(labels.contains("7 9 #11 13"), "\(labels)")
        XCTAssertTrue(upper.allSatisfy { $0.chord != nil })
        // Nothing with an avoid note: over Ionian, arpeggios containing the 4 (11) are left out
        let ionianUpper = ChordScaleMatcher.arpeggios(for: chord("major-7"), scale: scale("major"), chords: library.chords)
            .filter { $0.kind == .upperStructure }
        XCTAssertFalse(ionianUpper.contains { $0.degreesOverChord.contains(Degree(11)) })
    }

    func testKeyEstimation() {
        func key(_ text: String) -> String? {
            ChordScaleMatcher.estimateKey(text.split(separator: " ").map { parser.parse(String($0))! })?.description
        }
        XCTAssertEqual(key("Dm7 G7 Cmaj7"), "C major")
        XCTAssertEqual(key("Bbmaj7 Gm7 Cm7 F7"), "B♭ major")
        XCTAssertEqual(key("Am F C G Am"), "A minor")
        XCTAssertEqual(key("F#m7b5 B7 Em"), "E minor")
        XCTAssertNil(ChordScaleMatcher.estimateKey([]))
    }

    func testPlacementNearVoicing() throws {
        let fretboard = Fretboard()
        // Cmaj7 drop 2 at x3545x: the C major shape chosen should cover all of it
        let voicing: Set<FretPosition> = [.init(string: 1, fret: 3), .init(string: 2, fret: 5), .init(string: 3, fret: 4), .init(string: 4, fret: 5)]
        let shapes = ShapeGenerator.scalePositions(scale("major"), fretboard: fretboard)
        let near = try XCTUnwrap(ShapeGenerator.placement(of: shapes, root: PitchClass(0), on: fretboard, near: voicing))
        XCTAssertTrue(voicing.allSatisfy { near.placement[$0] != nil }, near.shape.name)
        XCTAssertTrue(near.placement.keys.allSatisfy { (1...8).contains($0.fret) }, "\(near.placement.keys.map(\.fret).sorted())")

        // Up at the 8th fret the shape moves with it
        let high: Set<FretPosition> = [.init(string: 0, fret: 8), .init(string: 2, fret: 9), .init(string: 3, fret: 9), .init(string: 4, fret: 8)]
        let nearHigh = try XCTUnwrap(ShapeGenerator.placement(of: shapes, root: PitchClass(0), on: fretboard, near: high))
        XCTAssertTrue(high.allSatisfy { nearHigh.placement[$0] != nil }, nearHigh.shape.name)
    }
}
