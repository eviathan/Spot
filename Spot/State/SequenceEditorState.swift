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
    
    /// Where to play one chord: a voicing of the chord, and the scale shape around it.
    struct NeckPosition {
        var name: String
        /// The scale shape.
        var placement: [FretPosition: ShapeNote]
        /// Where the hand is: the voicing's frets, or the scale's if there's no voicing.
        var centre: Double
        var voicing: ShapeOption?
        var position: ShapeOption?
    }

    /// A shape placed at one spot on the neck, to choose from.
    struct ShapeOption: Identifiable {
        var shape: Shape
        var placement: [FretPosition: ShapeNote]
        var pick: ShapePick
        /// Average fretted fret (open strings left out, so open chords count as first position).
        var centre: Double
        var id: String { "\(pick.shapeId)@\(pick.fret)" }

        /// e.g. "Drop 2 · Root position · fret 5", "CAGED · E shape · frets 5–8".
        var label: String {
            "\(shape.system) · \(shortLabel)"
        }

        /// Without the system: "E shape · frets 5–8".
        var shortLabel: String {
            let frets = placement.keys.map(\.fret)
            let low = frets.filter { $0 > 0 }.min() ?? 0, high = frets.max() ?? 0
            let where_ = low == high ? "fret \(low)" : (low == 0 ? "open–\(high)" : "frets \(low)–\(high)")
            // Generated names can start with the system ("Drop 3 · Root position"): it's shown separately
            var name = shape.name
            for separator in [" · ", ", ", " "] where name.hasPrefix(shape.system + separator) {
                name = String(name.dropFirst(shape.system.count + separator.count))
                break
            }
            return "\(name) · \(where_)"
        }

        init(shape: Shape, placement: [FretPosition: ShapeNote]) {
            self.shape = shape
            self.placement = placement
            let frets = placement.keys.map(\.fret)
            let fretted = frets.filter { $0 > 0 }
            pick = ShapePick(shapeId: shape.id, fret: fretted.min() ?? 0)
            centre = fretted.isEmpty ? 0 : Double(fretted.reduce(0, +)) / Double(fretted.count)
        }
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

    /// The playhead (empty, from a click) or a range (dragged), as in Live. Play starts from its start.
    var selection = BeatRange(0, 0) {
        didSet {
            if selection.start != playhead { playhead = selection.start }
        }
    }
    /// Where the selection starts (the playhead, while stopped). Its own property, so what only cares where the
    /// playhead is (the fretboard, NOW) isn't redrawn while a range is dragged out from it.
    private(set) var playhead: Double = 0
    /// The grid, as in Live: adaptive (following the zoom), fixed at a note value or a number of bars, or off.
    /// Remembered between sequences and launches.
    var grid: GridMode = GridMode.saved {
        didSet {
            if grid != .off { lastGrid = grid }
            UserDefaults.standard.set(grid.saveValue, forKey: GridMode.key)
        }
    }
    /// Triplet grid: every grid step ⅔ as long.
    var isTripletGrid: Bool = UserDefaults.standard.bool(forKey: GridMode.tripletKey) {
        didSet { UserDefaults.standard.set(isTripletGrid, forKey: GridMode.tripletKey) }
    }
    /// What the grid was before snapping was turned off (⌘4 turns it back on).
    @ObservationIgnored private var lastGrid: GridMode = .note(1)

    /// The grid now, in beats, for placing the playhead, selecting and moving and resizing chords; 0 is off.
    /// Adaptive, it depends on the zoom.
    var snap: Double {
        grid.beats(timeSignature: laneTimeSignature, beatWidth: beatWidth, triplet: isTripletGrid)
    }

    /// The grid now, named: "1/16", "1 Bar", "1/8T"…
    var gridName: String {
        GridMode.name(beats: snap, timeSignature: laneTimeSignature, triplet: isTripletGrid)
    }

    /// ⌘1: a finer grid (adaptive: narrower; fixed: the next shorter value).
    func narrowGrid() {
        switch grid {
        case .adaptive(let density): grid = .adaptive(density.narrower)
        case .off: grid = lastGrid
        default:
            let values = GridMode.fixed(timeSignature: laneTimeSignature)
            if let index = values.firstIndex(of: grid), index > 0 { grid = values[index - 1] }
        }
    }

    /// ⌘2: a wider grid.
    func widenGrid() {
        switch grid {
        case .adaptive(let density): grid = .adaptive(density.wider)
        case .off: grid = lastGrid
        default:
            let values = GridMode.fixed(timeSignature: laneTimeSignature)
            if let index = values.firstIndex(of: grid), index < values.count - 1 { grid = values[index + 1] }
        }
    }

    /// ⌘4: snapping off, or back on as it was.
    func toggleSnap() {
        grid = grid == .off ? lastGrid : .off
    }
    /// How long a chord put at the playhead is: the grid, but at least a beat.
    private var chordUnit: Double {
        snap >= 1 ? snap : 1
    }
    private var selectionAnchor: Double = 0

    /// Why the last chord picked couldn't be used.
    var chordError: String?
    /// How many beats before a change the next chord starts to show on the fretboard; nil for a bar (whatever the
    /// time signature), the default: a whole bar to see it coming.
    var ghostBeats: Double?

    /// The lead-up in beats, for a sequence (a bar of its time signature unless set).
    func leadUp(in sequence: ChordSequence) -> Double {
        ghostBeats ?? sequence.barLength
    }
    var neckView: NeckView = .followHand {
        didSet { refreshPositions() }
    }
    /// Where the hand starts: the first chord's position is the one nearest this fret.
    var handFret: Int = 5 {
        didSet { refreshPositions() }
    }
    /// Show a small diagram of the next chord in its position.
    var showsNextDiagram = true
    /// Show the rest of the next chord's scale on the fretboard, as well as its chord tones (off: just its chord
    /// tones, which is what you aim for, and less to take in).
    var showsNextScale = false
    /// The chord palette is open for the selection.
    var showsPalette = false
    /// A chord the fretboard holds on (its id), whatever's playing; nil to follow the playhead. One at a time.
    var pinnedChord: UUID?
    /// A pattern being renamed (its id), while the name box is up.
    var renamingPattern: UUID?
    /// Lane zoom: how wide a bar is, in points.
    var barWidth: Double = 140
    /// Lane scroll: the beat at the left edge while stopped (playing follows the playhead).
    var viewStart: Double = 0

    // What the lane last told us about itself, for zooming and clamping
    @ObservationIgnored private var viewportWidth: Double = 0
    @ObservationIgnored private var laneBeats: Double = 16
    @ObservationIgnored private var laneTimeSignature = TimeSignature(4, 4)
    /// A bar, in beats (quarter notes).
    private var laneBarLength: Double { laneTimeSignature.quarterNotes }

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
        barWidth / laneBarLength
    }
    /// How many beats fit on screen.
    var visibleBeats: Double {
        viewportWidth > 0 ? viewportWidth / beatWidth : laneBeats
    }
    /// Zoomed right out, the whole sequence fits.
    private var barWidthRange: ClosedRange<Double> {
        let fit = viewportWidth > 0 ? viewportWidth * laneBarLength / laneBeats : 40
        // In far enough to place markers on single samples
        return min(40, fit)...400_000
    }

    /// A beat to bring into view once the lane knows how wide it is (e.g. the start marker, on opening).
    @ObservationIgnored var revealOnLayout: Double?

    func setViewport(width: Double, lengthInBeats: Double, timeSignature: TimeSignature) {
        viewportWidth = width
        laneBeats = max(lengthInBeats, 1)
        laneTimeSignature = timeSignature
        if let beat = revealOnLayout, width > 0 {
            revealOnLayout = nil
            viewStart = beat - visibleBeats * 0.03
        }
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

    /// After playback stops: if following, scroll to the playhead when it's off screen. Otherwise the
    /// view stays where it is.
    func revealPlayhead() {
        guard followsPlayhead, viewportWidth > 0 else { return }
        let beat = selection.start
        if beat < viewStart || beat > viewStart + visibleBeats * 0.97 {
            scroll(to: beat - visibleBeats * 0.03)
        }
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
        barWidth = min(max(viewportWidth * laneBarLength / max(end - start, 0.25), range.lowerBound), range.upperBound)
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
    @ObservationIgnored private var optionCache: [String: [ShapeOption]] = [:]

    private(set) var analysis = Analysis()

    init(library: LibraryStore) {
        self.library = library
    }

    // MARK: - Analysis

    /// Scale suggestions already worked out, by chord, key and previous scale: songs repeat the same few chords, so
    /// most come round again (and with patterns, all of them do). Cleared when the library's scales change.
    @ObservationIgnored private var suggestionCache: [String: [ScaleSuggestion]] = [:]
    @ObservationIgnored private var cachedScaleIds: [String] = []

    func analyse(_ sequence: ChordSequence) {
        let scaleIds = library.scales.map(\.id)
        if scaleIds != cachedScaleIds {
            suggestionCache = [:]
            cachedScaleIds = scaleIds
        }
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
            let cacheKey = "\(chord.chord.id)|\(chord.root.pitchClass.value)|\(result.key.map(\.description) ?? "-")|"
                + "\(previous.map { "\($0.scale.id)@\($0.root.value)" } ?? "-")"
            let suggestions = suggestionCache[cacheKey] ?? {
                let worked = ChordScaleMatcher.scales(for: chord.chord, root: chord.root.pitchClass, among: library.scales,
                                                      context: ChordContext(key: result.key, previous: previous))
                suggestionCache[cacheKey] = worked
                return worked
            }()
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
    
    /// Walks through the chords choosing, for each, a voicing near the hand (or the one picked), then the scale
    /// shape that best surrounds it (or the one picked), and moving the hand to the voicing.
    private func positions(for sequence: ChordSequence, chords: [UUID: ChordSymbol],
                           scales: [UUID: ScaleDefinition]) -> [UUID: NeckPosition] {
        var result: [UUID: NeckPosition] = [:]
        var hand = Double(handFret)
        for region in sequence.chords {
            guard let chord = chords[region.id] else { continue }
            let voicings = voicingOptions(for: chord)
            let voicing = region.voicing.flatMap { pick in voicings.first { $0.pick == pick } }
                ?? voicings.min { abs($0.centre - hand) < abs($1.centre - hand) }

            var position: ShapeOption?
            if let scale = scales[region.id] {
                let options = positionOptions(for: chord, scale: scale)
                if let pick = region.position, let picked = options.first(where: { $0.pick == pick }) {
                    position = picked
                } else if let voicing {
                    // The scale shape that covers the voicing, under the same hand
                    let target = Set(voicing.placement.keys)
                    position = options.max { score($0, covering: target, at: voicing.centre) < score($1, covering: target, at: voicing.centre) }
                } else {
                    position = options.min { abs($0.centre - hand) < abs($1.centre - hand) }
                }
            }

            guard voicing != nil || position != nil else { continue }
            let name = [voicing.map { "\($0.shape.system), \($0.shape.name)" }, position.map { "\($0.shape.system), \($0.shape.name)" }]
                .compactMap { $0 }.joined(separator: " in ")
            let neck = NeckPosition(name: name, placement: position?.placement ?? [:],
                                    centre: voicing?.centre ?? position!.centre, voicing: voicing, position: position)
            result[region.id] = neck
            hand = neck.centre
        }
        return result
    }

    /// How well a scale shape surrounds a voicing: every voicing note it covers counts most, then closeness.
    private func score(_ option: ShapeOption, covering target: Set<FretPosition>, at centre: Double) -> Double {
        Double(target.filter { option.placement[$0] != nil }.count) * 10 - abs(option.centre - centre)
    }

    /// Every voicing of a chord on the neck (yours first, then generated ones), up the neck.
    func voicingOptions(for chord: ChordSymbol) -> [ShapeOption] {
        let key = "voicing:\(chord.chord.id):\(chord.root.pitchClass.value)"
        if let cached = optionCache[key] {
            return cached
        }
        let shapes = library.userShapes(for: chord.chord.id, tuningId: fretboard.tuning.id).filter { $0.kind == .chord }
            + ShapeGenerator.chordVoicings(chord.chord, root: chord.root.pitchClass, fretboard: fretboard)
        let options = shapes.flatMap { shape in
            shape.placements(root: chord.root.pitchClass, on: fretboard).map { ShapeOption(shape: shape, placement: $0) }
        }
        .sorted { $0.centre < $1.centre }
        optionCache[key] = options
        return options
    }

    /// Every placement of a scale's shapes for this chord's root, up the neck.
    func positionOptions(for chord: ChordSymbol, scale: ScaleDefinition) -> [ShapeOption] {
        let key = "scale:\(scale.id):\(scale.formula):\(chord.root.pitchClass.value)"
        if let cached = optionCache[key] {
            return cached
        }
        let options = scaleShapes(scale).flatMap { shape in
            shape.placements(root: chord.root.pitchClass, on: fretboard).map { ShapeOption(shape: shape, placement: $0) }
        }
        .sorted { $0.centre < $1.centre }
        optionCache[key] = options
        return options
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

    /// Puts the playhead at `beat` (on the grid line before it, or exactly there with the grid off),
    /// or extends the selection from where it was to there.
    func select(beat: Double, extend: Bool, in sequence: ChordSequence) {
        // The grid runs from 1.1.1 (the start marker)
        let point = max(0, min(sequence.onGrid(beat, unit: snap), sequence.lengthInBeats))
        if extend {
            selection = BeatRange(min(selectionAnchor, point), max(selectionAnchor, point))
        } else {
            selection = BeatRange(point, point)
            selectionAnchor = point
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
            start = sequence.onGrid(start, unit: unit)
            end = sequence.onGrid(end - 1e-9, unit: unit, .up)
        }
        start = max(0, start)
        end = min(sequence.lengthInBeats, max(end, start + (unit > 0 ? unit : 1.0 / 16)))
        selection = BeatRange(start, end)
        selectionAnchor = start
        chordError = nil
    }

    /// What a chord goes over: the selected range, or a grid unit from the playhead.
    func chordRange(in sequence: ChordSequence) -> BeatRange {
        guard selection.length == 0 else { return selection }
        return BeatRange(selection.start, min(selection.start + chordUnit, sequence.lengthInBeats))
    }

    /// The pinned chord, while it's still in the sequence.
    func pinnedRegion(in sequence: ChordSequence) -> ChordRegion? {
        guard let pinnedChord else { return nil }
        return sequence.chords.first { $0.id == pinnedChord }
    }

    /// Unpins whatever's pinned, or with nothing pinned, pins the chord at the selection.
    func togglePin(in sequence: ChordSequence) {
        pinnedChord = pinnedChord == nil ? sequence.chord(at: selection.start)?.id : nil
    }

    /// Moves the selection along by its own length (a grid unit from a playhead), for entering chord after chord.
    func advanceSelection(in sequence: ChordSequence) {
        let length = chordRange(in: sequence).length
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
        // A chord at the playhead becomes the selection, so the next one goes after it
        selection = chordRange(in: sequence)
        sequence.setChord(text, in: selection)
        chordError = nil
        return true
    }

    /// The playhead as bar.beat (with the sixteenth when it's between beats), or a range of bars, counted
    /// from 1.1.1 (bars before it are −1, −2…). Beats are the time signature's (eighths in 6/8).
    func describe(_ range: BeatRange, in sequence: ChordSequence) -> String {
        // Sixteenths in one of the time signature's beats: 4 in x/4, 2 in x/8, 1 in x/16 (none to show)
        let perBeat = max(1, Int((sequence.countUnit * 4).rounded()))
        let position = { (beat: Double) -> (bar: Int, beat: Int, sixteenth: Int) in
            let place = sequence.barAndBeat(at: beat)
            let sixteenth = Int(((place.beat - floor(place.beat)) * Double(perBeat)).rounded())
            return (place.bar, Int(place.beat + 1e-9) + 1, sixteenth > 0 && sixteenth < perBeat ? sixteenth + 1 : 0)
        }
        guard range.length > 0 else {
            let at = position(range.start)
            return "\(at.bar).\(at.beat)" + (at.sixteenth > 0 ? ".\(at.sixteenth)" : "")
        }
        let start = sequence.barAndBeat(at: range.start), end = sequence.barAndBeat(at: range.end)
        let lastBar = sequence.barAndBeat(at: range.end - 0.001).bar
        if start.beat < 0.001 && end.beat < 0.001 {
            return start.bar == lastBar ? "Bar \(start.bar)" : "Bars \(start.bar)–\(lastBar)"
        }
        let from = position(range.start), to = position(range.end - 0.001)
        return "\(from.bar).\(from.beat) – \(to.bar).\(to.beat)"
    }
}


/// How the lane's grid is chosen, as in Live.
enum GridMode: Hashable {
    /// Follows the zoom: the finest grid whose lines are at least so far apart.
    case adaptive(GridDensity)
    /// A note value, in quarter notes (1/16 is 0.25).
    case note(Double)
    /// A number of bars (½ for half a bar).
    case bars(Double)
    case off

    /// The grid in beats (quarter notes).
    func beats(timeSignature: TimeSignature, beatWidth: Double, triplet: Bool) -> Double {
        let scale = triplet ? 2.0 / 3 : 1
        let bar = timeSignature.quarterNotes
        switch self {
        case .off:
            return 0
        case .note(let quarters):
            return quarters * scale
        case .bars(let bars):
            return bars * bar * scale
        case .adaptive(let density):
            guard beatWidth > 0 else { return scale }
            // Note values shorter than a bar, half a bar when it halves evenly, then bars
            var candidates = [0.125, 0.25, 0.5, 1, 2].filter { $0 < bar - 1e-9 }
            if timeSignature.numerator % 2 == 0, timeSignature.numerator > 2, !candidates.contains(bar / 2) {
                candidates.append(bar / 2)
                candidates.sort()
            }
            var bars = 1.0
            while bars <= 1024 {
                candidates.append(bars * bar)
                bars *= 2
            }
            return (candidates.first { $0 * scale * beatWidth >= density.spacing } ?? candidates.last!) * scale
        }
    }

    /// The fixed grids, finest first (⌘1 and ⌘2 step through them).
    static func fixed(timeSignature: TimeSignature) -> [GridMode] {
        let bar = timeSignature.quarterNotes
        return [0.125, 0.25, 0.5, 1].filter { $0 < bar - 1e-9 }.map { .note($0) }
            + (timeSignature.numerator % 2 == 0 && timeSignature.numerator > 2 ? [.bars(0.5)] : [])
            + [.bars(1), .bars(2), .bars(4), .bars(8)]
    }

    /// "1/16", "½ Bar", "2 Bars", with T for triplets.
    static func name(beats: Double, timeSignature: TimeSignature, triplet: Bool) -> String {
        guard beats > 0 else { return "Off" }
        let bar = timeSignature.quarterNotes
        let plain = triplet ? beats * 3 / 2 : beats
        let t = triplet ? "T" : ""
        if plain >= bar - 1e-9 {
            let bars = plain / bar
            if abs(bars - bars.rounded()) < 1e-9 {
                return "\(Int(bars.rounded())) Bar\(Int(bars.rounded()) == 1 ? "" : "s")\(t)"
            }
        }
        if abs(plain - bar / 2) < 1e-9, timeSignature.numerator % 2 == 0, timeSignature.numerator > 2 { return "½ Bar\(t)" }
        let notes = 4 / plain
        if abs(notes - notes.rounded()) < 1e-9 { return "1/\(Int(notes.rounded()))\(t)" }
        return "\(String(format: "%g", plain)) beats\(t)"
    }

    // MARK: Saving

    static let key = "sequence.grid"
    static let tripletKey = "sequence.tripletGrid"

    static var saved: GridMode {
        UserDefaults.standard.string(forKey: key).flatMap(GridMode.init(saveValue:)) ?? .note(1)
    }

    var saveValue: String {
        switch self {
        case .adaptive(let density): return "adaptive:\(density.rawValue)"
        case .note(let quarters): return "note:\(quarters)"
        case .bars(let bars): return "bars:\(bars)"
        case .off: return "off"
        }
    }

    init?(saveValue: String) {
        let parts = saveValue.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "adaptive": guard let density = parts.last.flatMap(GridDensity.init(rawValue:)) else { return nil }; self = .adaptive(density)
        case "note": guard let value = parts.last.flatMap(Double.init) else { return nil }; self = .note(value)
        case "bars": guard let value = parts.last.flatMap(Double.init) else { return nil }; self = .bars(value)
        case "off": self = .off
        default: return nil
        }
    }
}

/// How fine the adaptive grid is: the least space between its lines.
enum GridDensity: String, CaseIterable {
    case narrowest, narrow, medium, wide, widest

    var spacing: Double {
        switch self {
        case .narrowest: return 6
        case .narrow: return 12
        case .medium: return 24
        case .wide: return 48
        case .widest: return 96
        }
    }

    var name: String { rawValue.capitalized }

    var narrower: GridDensity {
        GridDensity.allCases[max(0, (GridDensity.allCases.firstIndex(of: self) ?? 0) - 1)]
    }

    var wider: GridDensity {
        GridDensity.allCases[min(GridDensity.allCases.count - 1, (GridDensity.allCases.firstIndex(of: self) ?? 0) + 1)]
    }
}
