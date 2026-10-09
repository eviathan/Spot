import XCTest
@testable import SpotCore

final class ScaleShapeTests: XCTestCase {
    private var library: LibraryBundle!
    private let fretboard = Fretboard()

    override func setUpWithError() throws {
        library = try LibraryBundle.builtIn()
    }

    private func scale(_ id: String) -> ScaleDefinition {
        library.scales.first { $0.id == "builtin.scale." + id }!
    }

    /// Frets for each placed shape string, keyed by guitar string number (6 = low E).
    private func frets(_ shape: Shape, root: Int) -> [Int: [Int]] {
        let placement = shape.placements(root: PitchClass(root), on: fretboard).first!
        return Dictionary(grouping: placement.keys, by: { 6 - $0.string })
            .mapValues { $0.map(\.fret).sorted() }
    }

    /// The hand-entered E major patterns the app shipped with, high E string first.
    private let originalThreeNotePerString: [[[Int]]] = [
        [[2, 4, 5], [2, 4, 5], [1, 2, 4], [1, 2, 4], [0, 2, 4], [0, 2, 4]],
        [[4, 5, 7], [4, 5, 7], [2, 4, 6], [2, 4, 6], [2, 4, 6], [2, 4, 5]],
        [[5, 7, 9], [5, 7, 9], [4, 6, 8], [4, 6, 7], [4, 6, 7], [4, 5, 7]],
        [[7, 9, 11], [7, 9, 10], [6, 8, 9], [6, 7, 9], [6, 7, 9], [5, 7, 9]],
        [[9, 11, 12], [9, 10, 12], [8, 9, 11], [7, 9, 11], [7, 9, 11], [7, 9, 11]],
        [[11, 12, 14], [10, 12, 14], [9, 11, 13], [9, 11, 13], [9, 11, 12], [9, 11, 12]],
        [[12, 14, 16], [12, 14, 16], [11, 13, 14], [11, 13, 14], [11, 12, 14], [11, 12, 14]],
    ]

    func testThreeNotePerStringMatchesOriginalPatterns() {
        let shapes = ShapeGenerator.scalePositions(scale("major"), fretboard: fretboard)
        XCTAssertEqual(shapes.count, 12)
        XCTAssertEqual(shapes.first?.system, "3 notes per string")

        for (index, rows) in originalThreeNotePerString.enumerated() {
            let expected = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.offset + 1, $0.element) })
            XCTAssertEqual(frets(shapes[index], root: 4), expected, "Position \(index + 1)")
        }
    }

    func testModesStartOnTheirOwnRoot() {
        // A Dorian, position 1: low E string A B C (5 7 8)
        let shapes = ShapeGenerator.scalePositions(scale("dorian"), fretboard: fretboard)
        XCTAssertEqual(frets(shapes[0], root: 9)[6], [5, 7, 8])
    }

    func testWorksForEveryHeptatonicScale() {
        for scale in library.scales where scale.formula.degrees.count == 7 {
            let shapes = ShapeGenerator.scalePositions(scale, fretboard: fretboard).filter { $0.system == "3 notes per string" }
            XCTAssertEqual(shapes.count, 7, scale.id)
            for shape in shapes {
                XCTAssertEqual(shape.notes.count, 18, "\(scale.id) \(shape.name)")
                XCTAssertTrue(shape.notes.allSatisfy { scale.formula.degrees.contains($0.degree) })
                XCTAssertFalse(shape.placements(root: PitchClass(0), on: fretboard).isEmpty, "\(scale.id) \(shape.name)")
            }
        }
    }

    func testMinorPentatonicBoxes() {
        let shapes = ShapeGenerator.scalePositions(scale("minor-pentatonic"), fretboard: fretboard)
            .filter { $0.system == "2 notes per string" }
        XCTAssertEqual(shapes.count, 5)
        XCTAssertEqual(shapes[0].system, "2 notes per string")

        // A minor pentatonic box 1: 5-8 on every string except G (5-7) and D/A (5-7)
        XCTAssertEqual(frets(shapes[0], root: 9), [6: [5, 8], 5: [5, 7], 4: [5, 7], 3: [5, 7], 2: [5, 8], 1: [5, 8]])
        // Box 2 starts on C
        XCTAssertEqual(frets(shapes[1], root: 9), [6: [8, 10], 5: [7, 10], 4: [7, 10], 3: [7, 9], 2: [8, 10], 1: [8, 10]])
    }

    func testScaleFingering() {
        let shapes = ShapeGenerator.scalePositions(scale("major"), fretboard: fretboard)
        // G major position 1, low E string frets 3 5 7: a stretch, fingered 1 2 4
        let placement = shapes[0].placements(root: PitchClass(7), on: fretboard).first!
        let lowString = placement.filter { $0.key.string == 0 }.sorted { $0.key.fret < $1.key.fret }
        XCTAssertEqual(lowString.map(\.key.fret), [3, 5, 7])
        XCTAssertEqual(lowString.map(\.value.finger), [1, 2, 4])

        // E major position 1 at the nut: open, then fingers 1 and 3
        let atNut = shapes[0].placements(root: PitchClass(4), on: fretboard).first!
        XCTAssertEqual(atNut.filter { $0.key.string == 0 }.sorted { $0.key.fret < $1.key.fret }.map(\.value.finger), [0, 1, 3])

        XCTAssertEqual(Fingering.scaleFingers([2, 4, 5]), [1, 3, 4])
        XCTAssertEqual(Fingering.scaleFingers([2, 3, 5]), [1, 2, 4])
    }

    func testPlacementsRepeatEachOctave() {
        let shape = ShapeGenerator.scalePositions(scale("major"), fretboard: fretboard)[0]
        // E major position 1 spans frets 0-5, so it fits at 0 and 12
        XCTAssertEqual(shape.placements(root: PitchClass(4), on: fretboard).count, 2)
        XCTAssertEqual(shape.positions(root: PitchClass(4), on: fretboard).count, 36)
    }

    private func caged(_ id: String, _ name: String) -> Shape {
        ShapeGenerator.scalePositions(scale(id), fretboard: fretboard).first { $0.system == "CAGED" && $0.name == name }!
    }

    func testKnownCagedBoxes() {
        // G major, E shape: the standard box at frets 2-5
        XCTAssertEqual(frets(caged("major", "E shape"), root: 7),
                       [6: [2, 3, 5], 5: [2, 3, 5], 4: [2, 4, 5], 3: [2, 4, 5], 2: [3, 5], 1: [2, 3, 5]])
        // C major, C shape: the open position
        XCTAssertEqual(frets(caged("major", "C shape"), root: 0),
                       [6: [0, 1, 3], 5: [0, 2, 3], 4: [0, 2, 3], 3: [0, 2], 2: [0, 1, 3], 1: [0, 1, 3]])
        // G major, D shape: frets 4-8 with F# stretched to the D string's 4th fret
        XCTAssertEqual(frets(caged("major", "D shape"), root: 7)[4], [4, 5, 7])
    }

    func testCagedBoxesAreContinuousAndContainTheirChordForm() {
        // Movable major chord forms, frets relative to the box's root on its root string
        let chordForms: [String: [Int?]] = [
            "C shape": [nil, 3, 2, 0, 1, 0],   // C on the A string, 3rd fret
            "A shape": [nil, 0, 2, 2, 2, 0],   // A on the A string, open
            "G shape": [3, 2, 0, 0, 0, 3],     // G on the low E, 3rd fret
            "E shape": [0, 2, 2, 1, 0, 0],     // E on the low E, open
            "D shape": [nil, nil, 0, 2, 3, 2], // D on the D string, open
        ]
        let formRoots = ["C shape": 0, "A shape": 9, "G shape": 7, "E shape": 4, "D shape": 2]

        for (name, form) in chordForms {
            let placement = caged("major", name).positions(root: PitchClass(formRoots[name]!), on: fretboard)
            for (string, fret) in form.enumerated() {
                guard let fret else { continue }
                XCTAssertTrue(placement.keys.contains { $0.string == string && $0.fret % 12 == fret % 12 }, "\(name) string \(string) fret \(fret)")
            }
        }

        let scales = library.scales.filter { (5...7).contains($0.formula.degrees.count) }
        for scale in scales {
            let offsets = scale.formula.pitchClassOffsets
            for shape in ShapeGenerator.scalePositions(scale, fretboard: fretboard) where shape.system == "CAGED" {
                let placement = shape.placements(root: PitchClass(0), on: fretboard)[0]
                let pitches = placement.keys.map { fretboard.midiNote(at: $0) }.sorted()
                let label = "\(scale.id) \(shape.name)"

                XCTAssertEqual(Set(pitches.map { PitchClass($0).value }), offsets, label)
                for (low, high) in zip(pitches, pitches.dropFirst()) {
                    let skipped = (low + 1..<high).filter { offsets.contains(PitchClass($0).value) }
                    XCTAssertEqual(skipped, [], "\(label) skips a note between \(low) and \(high)")
                }
                let fretted = placement.keys.map(\.fret)
                XCTAssertLessThanOrEqual(fretted.max()! - fretted.min()!, 6, label)
            }
        }
    }

    func testCagedOnlyInStandardTuning() {
        XCTAssertTrue(ShapeGenerator.scalePositions(scale("major"), fretboard: Fretboard(tuning: .dropD)).allSatisfy { $0.system != "CAGED" })
    }

    func testOtherTunings() {
        let dropD = Fretboard(tuning: .dropD)
        let shapes = ShapeGenerator.scalePositions(scale("major"), fretboard: dropD)
        XCTAssertEqual(shapes.count, 7)
        // D major position 1 would dip below the nut on the A string in drop D, so it sits an octave up
        let placements = shapes[0].placements(root: PitchClass(2), on: dropD)
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(placements[0].filter { $0.key.string == 0 }.map(\.key.fret).sorted(), [12, 14, 16])
    }
}

final class ChordVoicingTests: XCTestCase {
    private var library: LibraryBundle!
    private let fretboard = Fretboard()

    override func setUpWithError() throws {
        library = try LibraryBundle.builtIn()
    }

    private func chord(_ id: String) -> ChordDefinition {
        library.chords.first { $0.id == "builtin.chord." + id }!
    }

    /// Voicings written low E to high E, "x" for muted, e.g. "x32010".
    private func tab(_ shape: Shape, root: Int) -> [String] {
        shape.placements(root: PitchClass(root), on: fretboard).map { placement in
            (0..<6).map { string in
                placement.first { $0.key.string == string }.map { String($0.key.fret) } ?? "x"
            }.joined()
        }
    }

    private func find(_ tab: String, in shapes: [Shape], root: Int) -> Shape? {
        shapes.first { self.tab($0, root: root).contains(tab) }
    }

    /// Suggested fingers for the first placement, low string first.
    private func fingers(_ shape: Shape, root: Int) -> [Int?] {
        let placement = shape.placements(root: PitchClass(root), on: fretboard).first!
        return placement.sorted { $0.key.string < $1.key.string }.map(\.value.finger)
    }

    func testFindsStandardOpenAndBarreChords() throws {
        let major = ShapeGenerator.chordVoicings(chord("major"), root: PitchClass(0), fretboard: fretboard)

        let openC = try XCTUnwrap(find("x32010", in: major, root: 0))
        XCTAssertEqual(openC.system, "Open")
        XCTAssertEqual(openC.name, "Open · Root position · strings 5–1")
        XCTAssertEqual(fingers(openC, root: 0), [3, 2, 0, 1, 0])

        let openG = try XCTUnwrap(find("320003", in: ShapeGenerator.chordVoicings(chord("major"), root: PitchClass(7), fretboard: fretboard), root: 7))
        XCTAssertEqual(fingers(openG, root: 7), [2, 1, 0, 0, 0, 3])

        let barreF = try XCTUnwrap(find("133211", in: ShapeGenerator.chordVoicings(chord("major"), root: PitchClass(5), fretboard: fretboard), root: 5))
        XCTAssertEqual(barreF.system, "Barre")
        XCTAssertEqual(fingers(barreF, root: 5), [1, 3, 4, 2, 1, 1])
    }

    func testInversionsAndDropVoicings() throws {
        let cmaj7 = ShapeGenerator.chordVoicings(chord("major-7"), root: PitchClass(0), fretboard: fretboard)

        // x3545x: C G B E, drop 2 in root position
        let drop2 = try XCTUnwrap(find("x3545x", in: cmaj7, root: 0))
        XCTAssertEqual(drop2.name, "Drop 2 · Root position · strings 5–2")

        // 8x998x: C B E G, drop 3
        let drop3 = try XCTUnwrap(find("8x998x", in: cmaj7, root: 0))
        XCTAssertEqual(drop3.system, "Drop 3")

        // xx2413: E B C G, drop 2 on the top four strings with E in the bass
        let firstInversion = try XCTUnwrap(find("xx2413", in: cmaj7, root: 0))
        XCTAssertEqual(firstInversion.name, "Drop 2 · 1st inversion · strings 4–1")
    }

    func testShellVoicing() throws {
        let g7 = ShapeGenerator.chordVoicings(chord("dominant-7"), root: PitchClass(7), fretboard: fretboard)
        // 3x34xx: G F B
        let shell = try XCTUnwrap(find("3x34xx", in: g7, root: 7))
        XCTAssertEqual(shell.system, "Shell")
    }

    func testEveryVoicingIsValid() {
        for chordId in ["major", "minor-7", "dominant-9", "half-diminished-7", "diminished-7", "power"] {
            let definition = chord(chordId)
            let required = Set(definition.requiredDegrees.map(\.pitchClassOffset))

            for root in [0, 4, 7, 10] {
                let voicings = ShapeGenerator.chordVoicings(definition, root: PitchClass(root), fretboard: fretboard)
                XCTAssertFalse(voicings.isEmpty, "\(chordId) root \(root)")
                XCTAssertEqual(Set(voicings.map(\.id)).count, voicings.count, "duplicate voicings for \(chordId)")

                for voicing in voicings {
                    XCTAssertTrue(required.isSubset(of: Set(voicing.notes.map(\.degree.pitchClassOffset))), voicing.name)
                    let fretted = voicing.placements(root: PitchClass(root), on: fretboard)[0].keys.map(\.fret).filter { $0 > 0 }
                    if let low = fretted.min(), let high = fretted.max() {
                        XCTAssertLessThanOrEqual(high - low, 3, voicing.name)
                    }
                    XCTAssertTrue(fingers(voicing, root: root).allSatisfy { ($0 ?? 9) <= 4 }, voicing.name)
                    XCTAssertFalse(voicing.placements(root: PitchClass(root), on: fretboard).isEmpty, voicing.name)
                }
            }
        }
    }

    func testCagedArpeggios() {
        let shapes = ShapeGenerator.chordShapes(chord("major-7"), root: PitchClass(0), fretboard: fretboard)
        let arpeggios = shapes.filter { $0.system == "CAGED arpeggio" }
        XCTAssertEqual(arpeggios.map(\.name), ["E shape", "D shape", "C shape", "A shape", "G shape"])

        let offsets = chord("major-7").formula.pitchClassOffsets
        for arpeggio in arpeggios {
            XCTAssertEqual(arpeggio.kind, .scale)
            let pitches = arpeggio.placements(root: PitchClass(0), on: fretboard)[0].keys.map { fretboard.midiNote(at: $0) }.sorted()
            XCTAssertEqual(Set(pitches.map { PitchClass($0).value }), offsets, arpeggio.name)
            for (low, high) in zip(pitches, pitches.dropFirst()) {
                XCTAssertEqual((low + 1..<high).filter { offsets.contains(PitchClass($0).value) }, [], arpeggio.name)
            }
        }
    }

    func testFingeringRules() {
        XCTAssertEqual(Fingering.chordFingers([nil, 3, 2, 0, 1, 0]), [1: 3, 2: 2, 3: 0, 4: 1, 5: 0])
        XCTAssertNil(Fingering.chordFingers([1, 2, 3, 4, 4, nil]), "needs five fingers")
    }
}
