//
//  PracticeState.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

/// The Chord Practice tab: a progression, the chord being practised, and what to play over it.
@Observable
final class PracticeState {
    /// What to draw around the chord voicing.
    enum Focus: Hashable {
        case scale
        case arpeggio(String)
    }

    let library: LibraryStore
    var fretboard = Fretboard()

    /// e.g. "Dm7 G7 Cmaj7". Saved between launches.
    var progressionText: String {
        didSet {
            UserDefaults.standard.set(progressionText, forKey: "practice.progression")
            parse()
        }
    }
    private(set) var chords: [ChordSymbol] = []
    /// Words in the progression that aren't chord symbols.
    private(set) var unreadable: [String] = []

    private(set) var index = 0
    /// nil means work the key out from the progression.
    var keyOverride: Key? {
        didSet { suggestionCache = [:] }
    }
    /// The scale chosen for each chord, by position in the progression; otherwise the top suggestion.
    private(set) var chosenScaleIds: [Int: String] = [:]
    var focus: Focus = .scale
    var voicingIndex = 0
    /// Only show one kind of voicing ("Drop 2", "Open"...); nil for all.
    var voicingSystem: String? {
        didSet { voicingIndex = 0 }
    }
    /// Show the scale or arpeggio across the whole neck instead of just around the voicing.
    var wholeNeck = false
    /// Colour notes by role (chord tone, tension, avoid) rather than by interval.
    var colourByRole = true

    @ObservationIgnored private var voicingCache: [String: [Shape]] = [:]
    /// Suggestions depend on every earlier chord's choice, so they're cached and cleared on any change.
    @ObservationIgnored private var suggestionCache: [Int: [ScaleSuggestion]] = [:]
    @ObservationIgnored private var cachedEstimatedKey: Key??
    @ObservationIgnored private var scaleShapeCache: [String: [Shape]] = [:]

    init(library: LibraryStore) {
        self.library = library
        self.progressionText = UserDefaults.standard.string(forKey: "practice.progression") ?? "Dm7 G7 Cmaj7"
        parse()
    }

    private func parse() {
        let parser = ChordSymbolParser(chords: library.chords)
        let words = progressionText.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "|" }).map(String.init)
        chords = words.compactMap(parser.parse)
        unreadable = words.filter { parser.parse($0) == nil }
        chosenScaleIds = [:]
        suggestionCache = [:]
        cachedEstimatedKey = nil
        index = min(index, max(chords.count - 1, 0))
    }

    // MARK: - Chords

    var current: ChordSymbol? {
        chords.indices.contains(index) ? chords[index] : nil
    }

    var key: Key? {
        keyOverride ?? estimatedKey
    }

    var estimatedKey: Key? {
        if let cachedEstimatedKey {
            return cachedEstimatedKey
        }
        let key = ChordScaleMatcher.estimateKey(chords)
        cachedEstimatedKey = .some(key)
        return key
    }

    func select(chordAt index: Int) {
        guard chords.indices.contains(index) else { return }
        self.index = index
        focus = .scale
    }

    func nextChord() {
        guard !chords.isEmpty else { return }
        select(chordAt: (index + 1) % chords.count)
    }

    func previousChord() {
        guard !chords.isEmpty else { return }
        select(chordAt: (index - 1 + chords.count) % chords.count)
    }

    // MARK: - Scales

    /// Ranked scales for the chord at `index`, taking the key and the previous chord's scale into account.
    func suggestions(at index: Int) -> [ScaleSuggestion] {
        guard chords.indices.contains(index) else { return [] }
        if let cached = suggestionCache[index] {
            return cached
        }
        let chord = chords[index]
        let previous = index > 0 ? chosenScale(at: index - 1).map { ($0, chords[index - 1].root.pitchClass) } : nil
        let suggestions = ChordScaleMatcher.scales(for: chord.chord, root: chord.root.pitchClass, among: library.scales,
                                                   context: ChordContext(key: key, previous: previous))
        suggestionCache[index] = suggestions
        return suggestions
    }

    func chosenScale(at index: Int) -> ScaleDefinition? {
        if let id = chosenScaleIds[index], let scale = library.scale(id) {
            return scale
        }
        return suggestions(at: index).first?.scale
    }

    var scaleSuggestions: [ScaleSuggestion] {
        suggestions(at: index)
    }

    var scale: ScaleDefinition? {
        chosenScale(at: index)
    }

    func choose(_ scale: ScaleDefinition) {
        chosenScaleIds[index] = scale.id
        suggestionCache = [:]
        focus = .scale
    }

    /// What each pitch class does over the current chord with the chosen scale (keyed by semitones above the root).
    var roles: [Int: NoteRole] {
        guard let current else { return [:] }
        guard let scale else {
            let tones = current.chord.formula.pitchClassOffsets
            return Dictionary(uniqueKeysWithValues: (0..<12).map { ($0, tones.contains($0) ? .chordTone : .outside) })
        }
        return ChordScaleMatcher.roles(chord: current.chord, scale: scale)
    }

    // MARK: - Arpeggios

    var arpeggios: [ArpeggioSuggestion] {
        guard let current else { return [] }
        return ChordScaleMatcher.arpeggios(for: current.chord, scale: scale, chords: library.chords)
    }

    var selectedArpeggio: ArpeggioSuggestion? {
        guard case .arpeggio(let id) = focus else { return nil }
        return arpeggios.first { $0.id == id }
    }

    /// e.g. "Em7" for an upper structure over Cmaj7, "B F" for guide tones.
    func name(of arpeggio: ArpeggioSuggestion) -> String {
        guard let current else { return "" }
        let root = current.root.spelling(arpeggio.degreesOverChord[0])
        switch arpeggio.kind {
        case .chord, .upperStructure:
            return root.description + (arpeggio.chord?.displaySymbol ?? "")
        case .guideTones:
            return arpeggio.degreesOverChord.map { current.root.spelling($0).description }.joined(separator: " ")
        }
    }

    // MARK: - Voicings

    private var allVoicings: [Shape] {
        guard let current else { return [] }
        let key = "\(fretboard.tuning.id):\(current.chord.id):\(current.chord.formula):\(current.root.pitchClass.value)"
        if let cached = voicingCache[key] {
            return cached
        }
        let voicings = library.userShapes(for: current.chord.id, tuningId: fretboard.tuning.id).filter { $0.kind == .chord }
            + ShapeGenerator.chordVoicings(current.chord, root: current.root.pitchClass, fretboard: fretboard)
        voicingCache[key] = voicings
        return voicings
    }

    var voicingSystems: [String] {
        var seen = Set<String>()
        return allVoicings.map(\.system).filter { seen.insert($0).inserted }
    }

    var voicings: [Shape] {
        guard let voicingSystem, voicingSystems.contains(voicingSystem) else { return allVoicings }
        return allVoicings.filter { $0.system == voicingSystem }
    }

    var currentVoicingIndex: Int? {
        let count = voicings.count
        return count == 0 ? nil : ((voicingIndex % count) + count) % count
    }

    var currentVoicing: Shape? {
        currentVoicingIndex.map { voicings[$0] }
    }

    func nextVoicing() {
        voicingIndex = (currentVoicingIndex ?? -1) + 1
    }

    func previousVoicing() {
        voicingIndex = (currentVoicingIndex ?? 1) - 1
    }

    var voicingPlacement: [FretPosition: ShapeNote]? {
        guard let current, let voicing = currentVoicing else { return nil }
        return voicing.placements(root: current.root.pitchClass, on: fretboard).first
    }

    // MARK: - What to play around the voicing

    /// The scale or arpeggio shape under the voicing's hand position, or nil when showing the whole neck.
    var focusPlacement: (name: String, placement: [FretPosition: ShapeNote])? {
        guard !wholeNeck, let current, let target = voicingPlacement.map({ Set($0.keys) }) else { return nil }

        switch focus {
        case .scale:
            guard let scale else { return nil }
            let shapes = scaleShapes(scale)
            return ShapeGenerator.placement(of: shapes, root: current.root.pitchClass, on: fretboard, near: target)
                .map { ("\(scale.name), \($0.shape.name)", $0.placement) }
        case .arpeggio:
            guard let arpeggio = selectedArpeggio else { return nil }
            let shapes = ShapeGenerator.caged(arpeggio.formula, definitionId: "practice.arpeggio",
                                              system: "Arpeggio", fretboard: fretboard)
            let root = current.root.pitchClass.transposed(by: arpeggio.rootOffset)
            return ShapeGenerator.placement(of: shapes, root: root, on: fretboard, near: target)
                .map { ("\(name(of: arpeggio)) arpeggio, \($0.shape.name)", $0.placement) }
        }
    }

    /// Pitch classes (as semitones above the chord root) of whatever is in focus.
    var focusOffsets: Set<Int> {
        guard let current else { return [] }
        switch focus {
        case .scale:
            return scale?.formula.pitchClassOffsets ?? current.chord.formula.pitchClassOffsets
        case .arpeggio:
            guard let arpeggio = selectedArpeggio else { return [] }
            return Set(arpeggio.formula.pitchClassOffsets.map { PitchClass($0 + arpeggio.rootOffset).value })
        }
    }

    private func scaleShapes(_ scale: ScaleDefinition) -> [Shape] {
        let key = "\(fretboard.tuning.id):\(scale.id):\(scale.formula)"
        if let cached = scaleShapeCache[key] {
            return cached
        }
        let shapes = library.userShapes(for: scale.id, tuningId: fretboard.tuning.id)
            + ShapeGenerator.scalePositions(scale, fretboard: fretboard)
        scaleShapeCache[key] = shapes
        return shapes
    }

    // MARK: - Listening

    func chordEvents(clock: TempoClock) -> [NoteEvent] {
        guard let voicingPlacement else { return [] }
        return Audition.chord(Audition.pitches(voicingPlacement.keys, on: fretboard), duration: max(1.2, clock.seconds(forBeats: 2)))
    }

    func focusEvents(clock: TempoClock) -> [NoteEvent] {
        guard let placement = focusPlacement?.placement else { return [] }
        return Audition.sequence(Audition.pitches(placement.keys, on: fretboard), noteLength: clock.seconds(forBeats: 0.5))
    }
}
