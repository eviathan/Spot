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
        /// Where to play each chord's scale, chosen to stay near the previous position.
        var positions: [UUID: NeckPosition] = [:]
    }
    
    /// A scale shape placed on the neck for one chord.
    struct NeckPosition {
        var name: String
        var placement: [FretPosition: ShapeNote]
        /// Average fret of the shape, i.e. where the hand is.
        var centre: Double
    }
    
    enum NeckView {
        /// Each chord's scale across the whole neck.
        case wholeNeck
        /// One position per chord, moving as little as possible from chord to chord.
        case followHand
    }

    /// Identifies this window to the playback controller.
    let id = UUID()
    let library: LibraryStore
    let fretboard = Fretboard()

    var selection = BeatRange(0, 4) {
        didSet { pausedAt = nil }
    }
    /// Where playback paused; Play carries on from here. Cleared by Stop or by selecting somewhere else.
    var pausedAt: Double?
    /// The grid in beats, for selecting and for moving and resizing chords; 0 is off.
    var snap: Double = 4
    /// What a click selects: the grid, but at least a beat (finer grids are for dragging).
    private var clickUnit: Double {
        snap >= 1 ? snap : 1
    }
    private var selectionAnchor: Double = 0

    /// Why the last chord picked couldn't be used.
    var chordError: String?
    /// How many beats before a change the next chord starts to show on the fretboard.
    var ghostBeats: Double = 2
    var neckView: NeckView = .followHand {
        didSet { refreshPositions() }
    }
    /// Where the hand starts: the first chord's position is the one nearest this fret.
    var handFret: Int = 5 {
        didSet { refreshPositions() }
    }
    /// Show a small diagram of the next chord in its position.
    var showsNextDiagram = true
    /// The chord palette is open for the selection.
    var showsPalette = false
    /// Lane zoom: how wide a bar is, in points.
    var barWidth: Double = 140
    /// Lane scroll: the beat at the left edge while stopped (playing follows the playhead).
    var viewStart: Double = 0

    // What the lane last told us about itself, for zooming and clamping
    @ObservationIgnored private var viewportWidth: Double = 0
    @ObservationIgnored private var laneBeats: Double = 16
    @ObservationIgnored private var laneBeatsPerBar: Double = 4

    /// While playing, page the lane along when the playhead reaches the edge.
    var followsPlayhead = true
    /// Scrolling by hand while playing stops following until the next Play.
    @ObservationIgnored var followSuspended = false

    enum ViewEdge { case start, end }

    /// Called every frame while playing: turns the page when the playhead goes off the view.
    func follow(_ beat: Double) {
        guard followsPlayhead, !followSuspended, viewportWidth > 0 else { return }
        let visible = visibleBeats
        if beat > viewStart + visible * 0.97 || beat < viewStart {
            scroll(to: beat - visible * 0.03)
        }
    }

    private var beatWidth: Double {
        barWidth / laneBeatsPerBar
    }
    /// How many beats fit on screen.
    var visibleBeats: Double {
        viewportWidth > 0 ? viewportWidth / beatWidth : laneBeats
    }
    /// Zoomed right out, the whole sequence fits.
    private var barWidthRange: ClosedRange<Double> {
        let fit = viewportWidth > 0 ? viewportWidth * laneBeatsPerBar / laneBeats : 40
        return min(40, fit)...1_200
    }

    func setViewport(width: Double, lengthInBeats: Double, beatsPerBar: Int) {
        viewportWidth = width
        laneBeats = max(lengthInBeats, 1)
        laneBeatsPerBar = Double(max(beatsPerBar, 1))
        clampView()
    }

    /// Zooms keeping the beat at `x` (points from the lane's left edge; the middle by default) where it is.
    func zoom(by factor: Double, around x: Double? = nil) {
        let anchorX = x ?? viewportWidth / 2
        let anchorBeat = viewStart + anchorX / beatWidth
        let range = barWidthRange
        barWidth = min(max(barWidth * factor, range.lowerBound), range.upperBound)
        viewStart = anchorBeat - anchorX / beatWidth
        clampView()
    }

    func pan(by points: Double) {
        viewStart += points / beatWidth
        clampView()
    }

    /// The person moved the view themselves (only matters while playing).
    func viewMovedByHand() {
        followSuspended = true
    }

    func scroll(to beat: Double) {
        viewStart = beat
        clampView()
    }

    /// Shows `start` to `end`, zooming to fit; if that's beyond the zoom limits, `keeping` that edge where asked.
    func show(from start: Double, to end: Double, keeping edge: ViewEdge = .start) {
        guard viewportWidth > 0 else { return }
        let range = barWidthRange
        barWidth = min(max(viewportWidth * laneBeatsPerBar / max(end - start, 0.25), range.lowerBound), range.upperBound)
        viewStart = edge == .start ? start : end - visibleBeats
        clampView()
    }

    func showAll() {
        show(from: 0, to: laneBeats)
    }

    private func clampView() {
        let range = barWidthRange
        let width = min(max(barWidth, range.lowerBound), range.upperBound)
        if width != barWidth { barWidth = width }
        let start = min(max(viewStart, 0), max(0, laneBeats - visibleBeats))
        if start != viewStart { viewStart = start }
    }
    
    @ObservationIgnored private var lastSequence: ChordSequence?
    @ObservationIgnored private var shapeCache: [String: [Shape]] = [:]

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
        result.positions = positions(for: sequence, chords: result.chords, scales: result.scales)
        analysis = result
        lastSequence = sequence
    }
    
    private func refreshPositions() {
        guard let lastSequence else { return }
        analysis.positions = positions(for: lastSequence, chords: analysis.chords, scales: analysis.scales)
    }
    
    /// Walks through the chords picking, for each, the scale position nearest the hand, then moving the hand there.
    private func positions(for sequence: ChordSequence, chords: [UUID: ChordSymbol],
                           scales: [UUID: ScaleDefinition]) -> [UUID: NeckPosition] {
        var result: [UUID: NeckPosition] = [:]
        var hand = Double(handFret)
        for region in sequence.chords {
            guard let chord = chords[region.id], let scale = scales[region.id] else { continue }
            let candidates = scaleShapes(scale).flatMap { shape in
                shape.placements(root: chord.root.pitchClass, on: fretboard).map { (shape, $0) }
            }
            let best = candidates.min { lhs, rhs in
                abs(centre(lhs.1) - hand) < abs(centre(rhs.1) - hand)
            }
            guard let (shape, placement) = best else { continue }
            let position = NeckPosition(name: "\(shape.system), \(shape.name)", placement: placement, centre: centre(placement))
            result[region.id] = position
            hand = position.centre
        }
        return result
    }
    
    private func centre(_ placement: [FretPosition: ShapeNote]) -> Double {
        let frets = placement.keys.map(\.fret)
        return Double(frets.reduce(0, +)) / Double(max(frets.count, 1))
    }
    
    private func scaleShapes(_ scale: ScaleDefinition) -> [Shape] {
        let key = "\(scale.id):\(scale.formula)"
        if let cached = shapeCache[key] {
            return cached
        }
        let shapes = library.userShapes(for: scale.id, tuningId: fretboard.tuning.id) + ShapeGenerator.scalePositions(scale, fretboard: fretboard)
        shapeCache[key] = shapes
        return shapes
    }

    func playback(for sequence: ChordSequence) -> SequencePlayback {
        SequencePlayback(length: sequence.lengthInBeats, loop: sequence.loop)
    }

    // MARK: - Selection

    /// Selects the grid unit at `beat`, or extends the selection to it.
    func select(beat: Double, extend: Bool, in sequence: ChordSequence) {
        let unit = clickUnit
        let start = max(0, min(floor(beat / unit) * unit, sequence.lengthInBeats - unit))
        if extend {
            selection = BeatRange(min(selectionAnchor, start), max(selectionAnchor + unit, start + unit))
        } else {
            selection = BeatRange(start, start + unit)
            selectionAnchor = start
        }
        chordError = nil
    }

    /// Selects exactly `range` (a chord), or extends the selection to cover it.
    func select(_ range: BeatRange, extend: Bool, in sequence: ChordSequence) {
        if extend {
            selection = BeatRange(min(selection.start, range.start), max(selection.end, range.end))
        } else {
            selection = range
            selectionAnchor = range.start
        }
        chordError = nil
    }

    /// Selects from one beat to another as dragged, out to the grid unless `free`.
    func selectRange(from first: Double, to second: Double, free: Bool, in sequence: ChordSequence) {
        let unit = free ? 0 : snap
        var start = min(first, second)
        var end = max(first, second)
        if unit > 0 {
            start = floor(start / unit) * unit
            end = ceil(end / unit) * unit
        }
        start = max(0, start)
        end = min(sequence.lengthInBeats, max(end, start + (unit > 0 ? unit : 1.0 / 16)))
        selection = BeatRange(start, end)
        selectionAnchor = start
        chordError = nil
    }

    /// Moves the selection along by its own length, for typing a chart chord after chord.
    func advanceSelection(in sequence: ChordSequence) {
        let length = selection.length
        let start = min(selection.end, sequence.lengthInBeats - length)
        selection = BeatRange(start, start + length)
        selectionAnchor = start
        chordError = nil
    }

    /// Puts a chord over the selection. Returns false (and sets `chordError`) if it isn't a chord.
    @discardableResult
    func applyChord(_ symbol: String, to sequence: inout ChordSequence) -> Bool {
        let text = symbol.trimmingCharacters(in: .whitespaces)
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
