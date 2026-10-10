//
//  SequenceEditorState.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

/// One sequence window's working state: the selection, and what each chord means (parsed chord, scale).
/// The sequence itself lives in the document.
@Observable
final class SequenceEditorState {
    /// What the chords resolve to. Rebuilt whenever the sequence changes.
    struct Analysis {
        var chords: [UUID: ChordSymbol] = [:]
        var scales: [UUID: ScaleDefinition] = [:]
        var suggestions: [UUID: [ScaleSuggestion]] = [:]
        var key: Key?
    }

    /// Identifies this window to the playback controller.
    let id = UUID()
    let library: LibraryStore
    let fretboard = Fretboard()

    var selection = BeatRange(0, 4)
    /// Selection size in beats: a bar, half a bar or a beat.
    var snap: Double = 4
    private var selectionAnchor: Double = 0

    /// The chord being typed in the editor bar.
    var chordText = ""
    var chordError: String?
    var sectionName = ""
    /// How many beats before a change the next chord starts to show on the fretboard.
    var ghostBeats: Double = 2

    private(set) var analysis = Analysis()

    init(library: LibraryStore) {
        self.library = library
    }

    // MARK: - Analysis

    func analyse(_ sequence: ChordSequence) {
        let parser = ChordSymbolParser(chords: library.chords)
        var result = Analysis()
        for region in sequence.chords {
            result.chords[region.id] = parser.parse(region.symbol)
        }

        let progression = sequence.chords.compactMap { result.chords[$0.id] }
        result.key = sequence.key ?? ChordScaleMatcher.estimateKey(progression)

        // Each chord's scale takes the previous chord's into account, as in Chord Practice
        var previous: (scale: ScaleDefinition, root: PitchClass)?
        for region in sequence.chords {
            guard let chord = result.chords[region.id] else { continue }
            let suggestions = ChordScaleMatcher.scales(for: chord.chord, root: chord.root.pitchClass, among: library.scales,
                                                       context: ChordContext(key: result.key, previous: previous))
            let scale = region.scaleId.flatMap(library.scale) ?? suggestions.first?.scale
            result.suggestions[region.id] = suggestions
            result.scales[region.id] = scale
            if let scale {
                previous = (scale, chord.root.pitchClass)
            }
        }
        analysis = result
    }

    func playback(for sequence: ChordSequence) -> SequencePlayback {
        SequencePlayback(notes: Backing.notes(for: sequence, chords: analysis.chords),
                         length: sequence.lengthInBeats,
                         loop: sequence.loop)
    }

    // MARK: - Selection

    /// Selects the snap unit at `beat`, or extends the selection to it.
    func select(beat: Double, extend: Bool, in sequence: ChordSequence) {
        let start = max(0, min(floor(beat / snap) * snap, sequence.lengthInBeats - snap))
        if extend {
            selection = BeatRange(min(selectionAnchor, start), max(selectionAnchor + snap, start + snap))
        } else {
            selection = BeatRange(start, start + snap)
            selectionAnchor = start
        }
        loadChordText(from: sequence)
    }

    /// Moves the selection along by its own length, for typing a chart chord after chord.
    func advanceSelection(in sequence: ChordSequence) {
        let length = selection.length
        let start = min(selection.end, sequence.lengthInBeats - length)
        selection = BeatRange(start, start + length)
        selectionAnchor = start
        loadChordText(from: sequence)
    }

    func loadChordText(from sequence: ChordSequence) {
        chordText = sequence.chord(at: selection.start)?.symbol ?? ""
        chordError = nil
    }

    /// Puts the typed chord over the selection. Returns false (and sets `chordError`) if it isn't a chord.
    @discardableResult
    func applyChord(to sequence: inout ChordSequence) -> Bool {
        let text = chordText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            sequence.clearChords(in: selection)
            return true
        }
        guard ChordSymbolParser(chords: library.chords).parse(text) != nil else {
            chordError = "“\(text)” isn't a chord Spot knows"
            return false
        }
        sequence.setChord(text, in: selection)
        chordError = nil
        return true
    }

    func describe(_ range: BeatRange, beatsPerBar: Int) -> String {
        let bpb = Double(beatsPerBar)
        let firstBar = Int(range.start / bpb) + 1
        let lastBar = Int((range.end - 0.001) / bpb) + 1
        let wholeBars = range.start.truncatingRemainder(dividingBy: bpb) == 0 && range.end.truncatingRemainder(dividingBy: bpb) == 0
        if wholeBars {
            return firstBar == lastBar ? "Bar \(firstBar)" : "Bars \(firstBar)–\(lastBar)"
        }
        let beat = { (b: Double) in "\(Int(b / bpb) + 1).\(Int(b.truncatingRemainder(dividingBy: bpb)) + 1)" }
        return "\(beat(range.start)) – \(beat(range.end - 0.001))"
    }
}
