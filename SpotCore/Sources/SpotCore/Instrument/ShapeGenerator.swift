//
//  ShapeGenerator.swift
//  SpotCore
//

import Foundation

/// Builds scale positions and chord voicings from a formula and a tuning.
public enum ShapeGenerator {

    // MARK: - Scales

    /// The positions for a scale: 3 notes per string for 7+ note scales, 2 notes per string
    /// (the pentatonic boxes) for 5 and 6 note scales, then the CAGED positions.
    public static func scalePositions(_ scale: ScaleDefinition, fretboard: Fretboard) -> [Shape] {
        let perString: [Shape]
        switch scale.formula.pitchClassOffsets.count {
        case 5...6: perString = notesPerString(2, formula: scale.formula, definitionId: scale.id, fretboard: fretboard)
        case 7...8: perString = notesPerString(3, formula: scale.formula, definitionId: scale.id, fretboard: fretboard)
        default: return []
        }
        return perString + caged(scale.formula, definitionId: scale.id, system: "CAGED", fretboard: fretboard)
    }

    /// The five CAGED boxes, each anchored on a movable major chord form. Frets are relative
    /// to the root on the low E string: the root sits at fret 7 on the A string and 2 on the D string.
    /// Each box is the chord form's frets widened to four, e.g. the E shape spans one fret below
    /// the root to two above.
    static let cagedWindows: [(name: String, low: Int, high: Int)] = [
        ("E shape", -1, 2),
        ("D shape", 2, 5),
        ("C shape", 4, 7),
        ("A shape", 6, 9),
        ("G shape", 9, 12),
    ]

    /// Every note of `formula` inside each CAGED box, plus a one-or-two-fret stretch wherever the box
    /// would otherwise skip a note between strings. Standard tuning only, since CAGED is built on it.
    public static func caged(_ formula: Formula, definitionId: String, system: String, fretboard: Fretboard) -> [Shape] {
        guard fretboard.tuning.strings == Tuning.standard.strings else {
            return []
        }

        let degreesByOffset = Dictionary(uniqueDegrees(formula).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let openStrings = fretboard.tuning.strings
        let rootPitch = openStrings[0]

        func offset(_ pitch: Int) -> Int {
            PitchClass(pitch - rootPitch).value
        }

        return cagedWindows.map { window in
            var notes: [FretPosition] = []
            for string in openStrings.indices {
                for fret in window.low...window.high where degreesByOffset[offset(openStrings[string] + fret)] != nil {
                    notes.append(FretPosition(string: string, fret: fret))
                }
            }

            // Fill any note of the formula skipped between adjacent box notes, reaching outside the box
            // by as little as possible (preferring the higher string, i.e. an index-finger stretch)
            func pitch(_ position: FretPosition) -> Int {
                openStrings[position.string] + position.fret
            }
            let sorted = notes.sorted { pitch($0) < pitch($1) }
            for (lower, upper) in zip(sorted, sorted.dropFirst()) where pitch(upper) - pitch(lower) > 1 {
                for missing in (pitch(lower) + 1)..<pitch(upper) where degreesByOffset[offset(missing)] != nil {
                    let candidates = (lower.string...upper.string).reversed()
                        .map { FretPosition(string: $0, fret: missing - openStrings[$0]) }
                        .filter { $0.fret >= window.low - 2 && $0.fret <= window.high + 2 }
                    let distance = { (p: FretPosition) in max(window.low - p.fret, p.fret - window.high, 0) }
                    if let best = candidates.min(by: { distance($0) < distance($1) }) {
                        notes.append(best)
                    }
                }
            }

            let shapeNotes = notes
                .sorted { ($0.string, $0.fret) < ($1.string, $1.fret) }
                .map { ShapeNote(string: $0.string, fret: $0.fret, degree: degreesByOffset[offset(pitch($0))]!) }

            return Shape(id: "generated:\(definitionId):caged:\(window.name)",
                         definitionId: definitionId,
                         kind: .scale,
                         system: system,
                         name: window.name,
                         tuningId: fretboard.tuning.id,
                         notes: shapeNotes)
        }
    }

    /// One position per scale degree: start on that degree on the lowest string and
    /// climb the scale, playing `count` notes on each string.
    public static func notesPerString(_ count: Int, formula: Formula, definitionId: String, fretboard: Fretboard) -> [Shape] {
        let degrees = uniqueDegrees(formula)
        let system = "\(count) notes per string"
        let lowestString = fretboard.tuning.strings[0]

        return degrees.indices.map { start in
            var notes: [ShapeNote] = []
            var index = start
            var octave = 0

            for string in 0..<fretboard.stringCount {
                var stringNotes: [ShapeNote] = []
                for _ in 0..<count {
                    let degree = degrees[index]
                    // Pitch relative to the root at fret 0 of the lowest string
                    let pitch = lowestString + degree.pitchClassOffset + octave * 12
                    stringNotes.append(ShapeNote(string: string, fret: pitch - fretboard.tuning.strings[string], degree: degree))

                    index += 1
                    if index == degrees.count {
                        index = 0
                        octave += 1
                    }
                }
                notes += stringNotes
            }

            return Shape(id: "generated:\(definitionId):\(count)nps:\(start + 1)",
                         definitionId: definitionId,
                         kind: .scale,
                         system: system,
                         name: "Position \(start + 1)",
                         tuningId: fretboard.tuning.id,
                         notes: notes)
        }
    }

    // MARK: - Chords

    /// Voicings for the chord followed by its CAGED arpeggio shapes.
    public static func chordShapes(_ chord: ChordDefinition, root: PitchClass, fretboard: Fretboard) -> [Shape] {
        chordVoicings(chord, root: root, fretboard: fretboard)
            + caged(chord.formula, definitionId: chord.id, system: "CAGED arpeggio", fretboard: fretboard)
    }

    /// Playable chord voicings with one note per string within `maxSpan` frets,
    /// for the given root, ordered up the neck.
    public static func chordVoicings(_ chord: ChordDefinition, root: PitchClass, fretboard: Fretboard, maxSpan: Int = 3) -> [Shape] {
        let degreesByOffset = Dictionary(uniqueDegrees(chord.formula).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let requiredOffsets = Set(chord.requiredDegrees.map(\.pitchClassOffset))
        let minimumNotes = max(requiredOffsets.count, min(3, degreesByOffset.count))
        let rootFret = Shape.rootFret(root, on: fretboard)

        var seen = Set<[Int?]>()
        var voicings: [(frets: [Int?], shape: Shape)] = []

        // Windows above the 12th fret repeat the ones below, so the shapes' octave placements cover them
        for windowStart in 0...min(11, fretboard.fretCount - maxSpan) {
            let low = max(1, windowStart)
            let high = windowStart + maxSpan
            // Open chords live in first position
            let allowOpen = windowStart <= 1

            let options: [[Int?]] = (0..<fretboard.stringCount).map { string in
                var frets: [Int?] = [nil]
                for fret in (allowOpen ? [0] : []) + Array(low...high) {
                    let offset = fretboard.pitchClass(at: FretPosition(string: string, fret: fret)).semitones(above: root)
                    if degreesByOffset[offset] != nil {
                        frets.append(fret)
                    }
                }
                return frets
            }

            enumerate(options, prefix: []) { frets in
                guard !seen.contains(frets),
                      let shape = makeVoicing(frets, chord: chord, root: root, degreesByOffset: degreesByOffset,
                                              requiredOffsets: requiredOffsets, minimumNotes: minimumNotes,
                                              rootFret: rootFret, fretboard: fretboard) else {
                    return
                }
                seen.insert(frets)
                voicings.append((frets, shape))
            }
        }

        return voicings
            .sorted { lhs, rhs in
                let l = (lhs.frets.compactMap { $0 }.filter { $0 > 0 }.min() ?? 0, lhs.frets.firstIndex { $0 != nil } ?? 0, -lhs.shape.notes.count)
                let r = (rhs.frets.compactMap { $0 }.filter { $0 > 0 }.min() ?? 0, rhs.frets.firstIndex { $0 != nil } ?? 0, -rhs.shape.notes.count)
                return l < r
            }
            .map(\.shape)
    }

    private static func enumerate(_ options: [[Int?]], prefix: [Int?], _ visit: ([Int?]) -> Void) {
        guard prefix.count < options.count else {
            visit(prefix)
            return
        }
        for option in options[prefix.count] {
            enumerate(options, prefix: prefix + [option], visit)
        }
    }

    private static func makeVoicing(_ frets: [Int?], chord: ChordDefinition, root: PitchClass,
                                    degreesByOffset: [Int: Degree], requiredOffsets: Set<Int>, minimumNotes: Int,
                                    rootFret: Int, fretboard: Fretboard) -> Shape? {
        let played = frets.indices.filter { frets[$0] != nil }
        guard played.count >= minimumNotes, let lowest = played.first, let highest = played.last else {
            return nil
        }

        // Anything wholly above the 12th fret repeats a lower voicing an octave up
        if played.allSatisfy({ frets[$0]! >= 12 }) {
            return nil
        }

        let interiorMutes = (highest - lowest + 1) - played.count
        if interiorMutes > 1 {
            return nil
        }

        let offsets = played.map { fretboard.pitchClass(at: FretPosition(string: $0, fret: frets[$0]!)).semitones(above: root) }
        guard requiredOffsets.isSubset(of: Set(offsets)) else {
            return nil
        }

        guard Fingering.chordFingers(frets) != nil else {
            return nil
        }

        let notes = zip(played, offsets).map { string, offset in
            ShapeNote(string: string, fret: frets[string]! - rootFret, degree: degreesByOffset[offset]!)
        }

        let system = voicingSystem(frets: frets, notes: notes, fretboard: fretboard)

        // Open chords ring through to the top string; only drop 3 and shell voicings skip a string
        if system == "Open", interiorMutes > 0 || highest != fretboard.stringCount - 1 {
            return nil
        }
        if interiorMutes > 0, system != "Drop 3", system != "Shell" {
            return nil
        }
        let bass = notes.min { fretboard.tuning.strings[$0.string] + frets[$0.string]! < fretboard.tuning.strings[$1.string] + frets[$1.string]! }!
        let name = [system, inversionName(bass: bass.degree, chord: chord), stringRangeName(lowest, highest, fretboard)]
            .joined(separator: " · ")
        let fretKey = frets.map { $0.map(String.init) ?? "x" }.joined(separator: "-")

        return Shape(id: "generated:\(chord.id):\(root.value):\(fretKey)",
                     definitionId: chord.id,
                     kind: .chord,
                     system: system,
                     name: name,
                     tuningId: fretboard.tuning.id,
                     notes: notes)
    }

    static func voicingSystem(frets: [Int?], notes: [ShapeNote], fretboard: Fretboard) -> String {
        if frets.contains(0) {
            return "Open"
        }

        let pitches = notes.map { fretboard.tuning.strings[$0.string] + (frets[$0.string] ?? 0) }.sorted()
        let distinctOffsets = Set(notes.map(\.degree.pitchClassOffset))
        let isContiguous = notes.count == (notes.last!.string - notes.first!.string + 1)

        if notes.count == 3, distinctOffsets.count == 3 {
            let simple = Set(notes.map { ($0.degree.number - 1) % 7 + 1 })
            if simple.contains(1), simple.contains(3), simple.contains(7) || notes.contains(where: { $0.degree == Degree("bb7") }) {
                return "Shell"
            }
            return isContiguous ? "Triad" : "Spread triad"
        }

        if notes.count == 4, distinctOffsets.count == 4 {
            if isClose(pitches) {
                return "Close"
            }
            // Drop voicings put the dropped voice in the bass. Raising it back an octave gives a close
            // voicing, and where it lands says which voice was dropped: 2nd from the top or 3rd.
            let raised = (pitches.dropFirst() + [pitches[0] + 12]).sorted()
            if isClose(raised) {
                switch raised.count - 1 - raised.firstIndex(of: pitches[0] + 12)! {
                case 1: return "Drop 2"
                case 2: return "Drop 3"
                default: break
                }
            }
        }

        return notes.count >= 5 && sharesLowestFret(frets) ? "Barre" : "Other"
    }

    private static func isClose<C: Collection>(_ pitches: C) -> Bool where C.Element == Int {
        pitches.max()! - pitches.min()! < 12
    }

    private static func sharesLowestFret(_ frets: [Int?]) -> Bool {
        let fretted = frets.compactMap { $0 }.filter { $0 > 0 }
        guard let minFret = fretted.min() else { return false }
        return fretted.filter { $0 == minFret }.count >= 2
    }

    static func inversionName(bass: Degree, chord: ChordDefinition) -> String {
        guard let index = chord.formula.degrees.firstIndex(where: { $0.pitchClassOffset == bass.pitchClassOffset }) else {
            return "\(bass) in bass"
        }
        switch index {
        case 0: return "Root position"
        case 1: return "1st inversion"
        case 2: return "2nd inversion"
        case 3: return "3rd inversion"
        default: return "\(bass.prettyDescription) in bass"
        }
    }

    /// Guitarists number strings from the highest (1) to the lowest.
    static func stringRangeName(_ lowest: Int, _ highest: Int, _ fretboard: Fretboard) -> String {
        "strings \(fretboard.stringCount - lowest)–\(fretboard.stringCount - highest)"
    }

    private static func uniqueDegrees(_ formula: Formula) -> [Degree] {
        var seen = Set<Int>()
        return formula.degrees
            .sorted { $0.pitchClassOffset < $1.pitchClassOffset }
            .filter { seen.insert($0.pitchClassOffset).inserted }
    }
}
