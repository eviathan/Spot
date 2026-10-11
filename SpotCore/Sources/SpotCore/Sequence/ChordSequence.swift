//
//  ChordSequence.swift
//  SpotCore
//

import Foundation

/// A span of musical time in beats, `start` included and `end` not.
public struct BeatRange: Hashable, Codable, Sendable {
    public var start: Double
    public var end: Double

    public init(_ start: Double, _ end: Double) {
        self.start = start
        self.end = max(start, end)
    }

    public var length: Double {
        end - start
    }

    public func contains(_ beat: Double) -> Bool {
        beat >= start && beat < end
    }

    public func overlaps(_ other: BeatRange) -> Bool {
        start < other.end && other.start < end
    }
}

/// Something placed on the timeline that mustn't overlap others of its kind.
protocol BeatRanged {
    var id: UUID { get set }
    var range: BeatRange { get set }
}

/// A chord over part of the sequence, written as a symbol ("Dm7", "Bb7#9/D") so files stay readable.
/// A shape placed on the neck: which shape (by id), and where (the fret of its lowest fretted note).
public struct ShapePick: Hashable, Codable, Sendable {
    public var shapeId: String
    public var fret: Int

    public init(shapeId: String, fret: Int) {
        self.shapeId = shapeId
        self.fret = fret
    }
}

public struct ChordRegion: Identifiable, Hashable, Codable, Sendable, BeatRanged {
    public var id: UUID
    public var range: BeatRange
    public var symbol: String
    /// A scale chosen for this chord; nil to use the best suggestion.
    public var scaleId: String?
    /// How to play the chord, chosen by hand; nil to pick one near the hand.
    public var voicing: ShapePick?
    /// Where to play the scale, chosen by hand; nil to pick the one around the voicing.
    public var position: ShapePick?

    public init(id: UUID = UUID(), range: BeatRange, symbol: String, scaleId: String? = nil) {
        self.id = id
        self.range = range
        self.symbol = symbol
        self.scaleId = scaleId
    }
}

/// A named part of the song, e.g. "Verse".
public struct SequenceSection: Identifiable, Hashable, Codable, Sendable, BeatRanged {
    public var id: UUID
    public var name: String
    public var range: BeatRange

    public init(id: UUID = UUID(), name: String, range: BeatRange) {
        self.id = id
        self.name = name
        self.range = range
    }
}

/// A song's chords on a beat grid: the contents of a `.spot` file.
public struct ChordSequence: Hashable, Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var tempo: Double
    /// Any time signature (7/8, 12/8, 5/4…). Beats here are quarter notes, as in Live: the tempo counts them and
    /// everything is placed in them, so a bar of 7/8 is 3½ beats long. Bars and the "bar.beat" count go by the time
    /// signature (`barLength`, `countUnit`).
    public var timeSignature: TimeSignature
    public var lengthInBars: Int
    /// nil to work the key out from the chords.
    public var key: Key?
    /// The song's chords as they're heard: the plain ones and the patterns' laid out where they're used, round
    /// after round. Sorted by start, never overlapping. (Worked out from `looseChords`, `patterns` and `instances`.)
    public private(set) var chords: [ChordRegion]
    /// For each chord in `chords` that comes from a pattern: which, and where.
    public private(set) var chordSources: [UUID: ChordSource]
    /// Chords that aren't in a pattern. Sorted, not overlapping, and not under a pattern.
    public internal(set) var looseChords: [ChordRegion]
    public internal(set) var patterns: [ChordPattern]
    /// Where patterns are used. Sorted, not overlapping.
    public internal(set) var instances: [PatternInstance]
    /// The loop brace: kept when looping is off, so it can be shown and turned back on.
    public var loopRange: BeatRange?
    public var isLooping: Bool
    /// The loop in use: the range while looping, otherwise nil. Setting a range turns looping on; nil turns it
    /// off (the range is kept).
    public var loop: BeatRange? {
        get { isLooping ? loopRange : nil }
        set {
            if let newValue {
                loopRange = newValue
                isLooping = true
            } else {
                isLooping = false
            }
        }
    }
    /// A recording to play along with, lined up by warp markers.
    public var audio: AudioTrack?
    /// Your recordings, oldest first.
    public var takes: [RecordedTake]
    /// The sequence's tab (tablature): it plays along, its bar 1 on the start marker and its quarter notes on the
    /// sequence's beats (at the sequence's tempo, not its own). nil until one is written.
    public var tablature: TabScore?
    public var tabIsMuted: Bool
    /// Where bar 1 beat 1 is, like Live's start marker: bars, beats and the grid count from here, and
    /// anything before it is in the bars before 1 (−1, −2…). Nothing moves when it does.
    public var startBeat: Double
    /// Where the song ends (playback stops there); nil to end with the bar the last thing ends in.
    public var endBeat: Double?

    public init(tempo: Double = 100, timeSignature: TimeSignature = TimeSignature(4, 4), lengthInBars: Int = 16) {
        self.version = ChordSequence.currentVersion
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.lengthInBars = lengthInBars
        self.key = nil
        self.chords = []
        self.chordSources = [:]
        self.looseChords = []
        self.patterns = []
        self.instances = []
        self.loopRange = nil
        self.isLooping = false
        self.audio = nil
        self.takes = []
        self.tablature = nil
        self.tabIsMuted = false
        self.startBeat = 0
        self.endBeat = nil
    }

    /// x/4, for older code and files that only knew beats to the bar.
    public init(tempo: Double = 100, beatsPerBar: Int, lengthInBars: Int = 16) {
        self.init(tempo: tempo, timeSignature: TimeSignature(beatsPerBar, 4), lengthInBars: lengthInBars)
    }

    /// How long a bar is, in beats (quarter notes): 4 in 4/4, 3½ in 7/8, 6 in 12/8.
    public var barLength: Double {
        timeSignature.quarterNotes
    }

    /// What the bar is counted in, in beats: a quarter note in x/4, an eighth in x/8.
    public var countUnit: Double {
        timeSignature.countUnit
    }

    public var lengthInBeats: Double {
        Double(lengthInBars) * barLength
    }

    public func bar(_ index: Int) -> BeatRange {
        BeatRange(Double(index) * barLength, Double(index + 1) * barLength)
    }

    // MARK: - Reading

    public func chord(at beat: Double) -> ChordRegion? {
        chords.first { $0.range.contains(beat) }
    }

    /// The next chord to start after `beat`.
    public func chord(after beat: Double) -> ChordRegion? {
        chords.first { $0.range.start > beat }
    }

    /// The chord that comes after the one playing at `beat`, and how many beats until it starts. While looping,
    /// the last chord in the loop is followed by the one at the loop's start (arriving at the loop's end).
    public func upcomingChord(at beat: Double) -> (chord: ChordRegion, beatsAway: Double)? {
        let current = chord(at: max(beat, 0))
        let next = chord(after: max(beat, current?.range.start ?? beat))
        if let loop, beat >= loop.start - 1e-9, beat < loop.end, next.map({ $0.range.start >= loop.end - 1e-9 }) ?? true {
            // Round to the top of the loop: whatever's playing at its start (or the first chord inside it)
            guard let first = chord(at: loop.start) ?? chord(after: loop.start).flatMap({ $0.range.start < loop.end ? $0 : nil }),
                  first.id != current?.id else { return nil }
            return (first, loop.end - beat + max(0, first.range.start - loop.start))
        }
        return next.map { ($0, $0.range.start - beat) }
    }

    // MARK: - Editing

    /// Works `chords` out again after a change.
    mutating func rebuild() {
        (chords, chordSources) = ChordSequence.layOut(loose: looseChords, patterns: patterns, instances: instances)
    }

    /// Several changes, then `chords` worked out once.
    mutating func editAll(_ change: (inout ChordSequence) -> Void) {
        change(&self)
        rebuild()
    }

    /// The part of `range` outside patterns, from its start (plain chords stop where a pattern begins).
    private func outsidePatterns(_ range: BeatRange) -> BeatRange {
        let end = instances.first { $0.range.start >= range.start - 1e-9 && $0.range.start < range.end }?.range.start ?? range.end
        return BeatRange(range.start, end)
    }

    /// Puts a chord over `range`, trimming or splitting whatever was there. Inside a pattern it goes into the
    /// pattern (so every time round, and every place it's used, gets it), within that time round.
    public mutating func setChord(_ symbol: String, in range: BeatRange, scaleId: String? = nil) {
        let range = clamped(range)
        guard range.length > 0 else { return }
        if let round = round(at: range.start) {
            let end = min(range.end, round.instance.range.end, round.roundStart + round.pattern.length)
            setPatternChord(round.pattern.id, ChordRegion(range: BeatRange(range.start - round.roundStart, end - round.roundStart),
                                                          symbol: symbol, scaleId: scaleId))
        } else {
            let plain = outsidePatterns(range)
            guard plain.length > 0 else { return }
            looseChords = ChordSequence.carve(looseChords, removing: plain)
            looseChords.append(ChordRegion(range: plain, symbol: symbol, scaleId: scaleId))
            looseChords.sort { $0.range.start < $1.range.start }
        }
        rebuild()
    }

    /// Puts an existing chord (moved or resized) at its new range, keeping its id and scale,
    /// and trims whatever it now covers. A pattern's chord moves within its pattern.
    public mutating func place(_ region: ChordRegion) {
        var region = region
        region.range = clamped(region.range)
        guard region.range.length > 0 else { return }
        if let source = chordSources[region.id] {
            var chord = region
            chord.id = source.chordId
            chord.range = BeatRange(region.range.start - source.roundStart, region.range.end - source.roundStart)
            setPatternChord(source.patternId, chord)
        } else {
            region.range = outsidePatterns(region.range)
            guard region.range.length > 0 else { return }
            looseChords.removeAll { $0.id == region.id }
            looseChords = ChordSequence.carve(looseChords, removing: region.range)
            looseChords.append(region)
            looseChords.sort { $0.range.start < $1.range.start }
        }
        rebuild()
    }

    /// Clears chords in `range`. Patterns wholly inside it go (as in Live, deleting a selected clip); where it's
    /// over part of one, its chords there are cleared from the pattern (every time round, and in its copies).
    public mutating func clearChords(in range: BeatRange) {
        looseChords = ChordSequence.carve(looseChords, removing: range)
        instances.removeAll { range.start <= $0.range.start + 1e-9 && $0.range.end <= range.end + 1e-9 }
        patterns.removeAll { pattern in !instances.contains { $0.patternId == pattern.id } }
        for instance in instances where instance.range.overlaps(range) {
            guard let pattern = pattern(instance.patternId) else { continue }
            var roundStart = instance.range.start - instance.phase
            while roundStart < min(instance.range.end, range.end) {
                let from = max(range.start, instance.range.start) - roundStart
                let to = min(range.end, instance.range.end) - roundStart
                if to > 0 && from < pattern.length {
                    clearPatternChords(pattern.id, in: BeatRange(max(0, from), min(pattern.length, to)))
                }
                roundStart += pattern.length
            }
        }
        rebuild()
    }

    /// Changes one chord's symbol or scale without moving it (a pattern's: every time it comes round).
    /// Changing the chord forgets its voicing and position; changing its scale forgets the position.
    public mutating func update(_ id: UUID, symbol: String? = nil, scaleId: String?? = nil) {
        edit(id) { chord in
            if let symbol, symbol != chord.symbol {
                chord.symbol = symbol
                chord.voicing = nil
                chord.position = nil
            }
            if let scaleId, scaleId != chord.scaleId {
                chord.scaleId = scaleId
                chord.position = nil
            }
        }
    }

    /// Chooses (or, with nil, stops choosing) a chord's voicing or scale position.
    public mutating func pick(_ id: UUID, voicing: ShapePick?? = nil, position: ShapePick?? = nil) {
        edit(id) { chord in
            if let voicing { chord.voicing = voicing }
            if let position { chord.position = position }
        }
    }

    /// Changes a chord in `chords`: a plain one, or (one from a pattern) the pattern's.
    private mutating func edit(_ id: UUID, _ change: (inout ChordRegion) -> Void) {
        if let source = chordSources[id] {
            editPatternChord(source.patternId, source.chordId, change)
        } else if let index = looseChords.firstIndex(where: { $0.id == id }) {
            change(&looseChords[index])
        } else {
            return
        }
        rebuild()
    }

    /// Changes the length, dropping or trimming anything past the new end.
    public mutating func setLength(bars: Int) {
        lengthInBars = max(1, bars)
        let end = lengthInBeats
        looseChords = ChordSequence.carve(looseChords, removing: BeatRange(end, .infinity))
        instances = instances.compactMap { instance in
            guard instance.range.start < end - 1e-9 else { return nil }
            var trimmed = instance
            trimmed.range = BeatRange(instance.range.start, min(instance.range.end, end))
            return trimmed
        }
        patterns.removeAll { pattern in !instances.contains { $0.patternId == pattern.id } }
        rebuild()
        if let loopRange, loopRange.start >= end {
            self.loopRange = nil
            isLooping = false
        } else if let loopRange {
            self.loopRange = BeatRange(loopRange.start, min(loopRange.end, end))
        }
        startBeat = min(startBeat, max(0, end - 1))
        if let endBeat, endBeat > end || endBeat <= startBeat {
            self.endBeat = nil
        }
    }

    // MARK: - Bars, counted from the start marker

    /// `beat` moved onto the grid of `unit` beats that runs from the start marker.
    public func onGrid(_ beat: Double, unit: Double, _ rule: FloatingPointRoundingRule = .down) -> Double {
        guard unit > 0 else { return beat }
        return startBeat + ((beat - startBeat) / unit + (rule == .down ? 1e-9 : 0)).rounded(rule) * unit
    }

    /// The bar a beat is in (1 from the start marker; the bars before it are −1, −2…) and how far into that bar
    /// it is (from 0), counted in the time signature's unit (eighths in 6/8).
    public func barAndBeat(at beat: Double) -> (bar: Int, beat: Double) {
        let bar = barLength
        let index = Int(floor((beat - startBeat) / bar + 1e-9))
        let within = beat - startBeat - Double(index) * bar
        return (index >= 0 ? index + 1 : index, max(0, within) / countUnit)
    }

    /// Where playback stops: the end marker, or the end of the bar the last thing ends in.
    public var songEnd: Double {
        if let endBeat {
            return endBeat
        }
        let content = contentEnd
        guard content > startBeat else { return lengthInBeats }
        return min(lengthInBeats, onGrid(content - 1e-9, unit: barLength, .up))
    }

    /// Where the recording ends on the grid (through its warp markers), if there is one.
    public var audioEndBeat: Double? {
        audio.map { $0.map.beat(atSourceTime: $0.reference.duration) }
    }

    /// Where the last thing ends: a chord, a pattern, a take, the recording or the tab's last notes.
    public var contentEnd: Double {
        max(chords.last?.range.end ?? 0, instances.map(\.range.end).max() ?? 0,
            takes.map(\.endBeat).max() ?? 0, audioEndBeat ?? 0, endBeat ?? 0,
            tablature.map { startBeat + $0.contentQuarterNotes } ?? 0)
    }

    /// Sizes the sequence to what's in it, plus `spareBars` empty bars to add more (and at least `minimumBars`).
    public mutating func fitLength(spareBars: Int = 4, minimumBars: Int = 16) {
        let used = Int(ceil(contentEnd / barLength - 1e-9))
        let bars = max(minimumBars, used + spareBars)
        if bars != lengthInBars {
            setLength(bars: bars)
        }
    }

    private func clamped(_ range: BeatRange) -> BeatRange {
        BeatRange(max(0, range.start), min(lengthInBeats, range.end))
    }

    /// Removes `removing` from a list of non-overlapping items: trims items at its edges and
    /// splits one that spans it (the second half gets a new id).
    static func carve<Item: BeatRanged>(_ items: [Item], removing: BeatRange) -> [Item] {
        items.flatMap { item -> [Item] in
            guard item.range.overlaps(removing) else { return [item] }

            var pieces: [Item] = []
            if item.range.start < removing.start {
                var before = item
                before.range = BeatRange(item.range.start, removing.start)
                pieces.append(before)
            }
            if item.range.end > removing.end {
                var after = item
                after.range = BeatRange(removing.end, item.range.end)
                if !pieces.isEmpty {
                    after.id = UUID()
                }
                pieces.append(after)
            }
            return pieces
        }
    }

    // MARK: - Files

    enum CodingKeys: String, CodingKey {
        // `chords` are the plain ones (as files before patterns had them)
        case version, tempo, timeSignature, lengthInBars, key, chords, patterns, patternInstances, loopRange, isLooping, audio, takes, tablature, tabIsMuted, startBeat, endBeat
    }

    private enum LegacyKeys: String, CodingKey {
        case practiceRate, loop, beatsPerBar, sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version <= ChordSequence.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Made by a newer version of Spot (format \(version))")
        }
        tempo = try container.decode(Double.self, forKey: .tempo)
        // Files from before any time signature had beats to the bar (of quarter notes)
        if let signature = try container.decodeIfPresent(TimeSignature.self, forKey: .timeSignature) {
            timeSignature = signature
        } else {
            timeSignature = TimeSignature(try decoder.container(keyedBy: LegacyKeys.self).decode(Int.self, forKey: .beatsPerBar), 4)
        }
        lengthInBars = try container.decode(Int.self, forKey: .lengthInBars)
        key = try container.decodeIfPresent(Key.self, forKey: .key)
        looseChords = (try container.decodeIfPresent([ChordRegion].self, forKey: .chords) ?? []).sorted { $0.range.start < $1.range.start }
        patterns = try container.decodeIfPresent([ChordPattern].self, forKey: .patterns) ?? []
        instances = (try container.decodeIfPresent([PatternInstance].self, forKey: .patternInstances) ?? []).sorted { $0.range.start < $1.range.start }
        chords = []
        chordSources = [:]
        loopRange = try container.decodeIfPresent(BeatRange.self, forKey: .loopRange)
        isLooping = try container.decodeIfPresent(Bool.self, forKey: .isLooping) ?? false
        // Older files: a loop was on whenever there was one
        if let oldLoop = try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(BeatRange.self, forKey: .loop) {
            loopRange = oldLoop
            isLooping = true
        }
        audio = try container.decodeIfPresent(AudioTrack.self, forKey: .audio)
        // Older files: the sequence tempo was the recording's, and a practice speed slowed both
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let practiceRate = try legacy.decodeIfPresent(Double.self, forKey: .practiceRate) ?? 1
        if audio?.tempo == 0 {
            audio?.tempo = tempo
        }
        tempo *= practiceRate
        takes = try container.decodeIfPresent([RecordedTake].self, forKey: .takes) ?? []
        tablature = try container.decodeIfPresent(TabScore.self, forKey: .tablature)
        tabIsMuted = try container.decodeIfPresent(Bool.self, forKey: .tabIsMuted) ?? false
        startBeat = try container.decodeIfPresent(Double.self, forKey: .startBeat) ?? 0
        endBeat = try container.decodeIfPresent(Double.self, forKey: .endBeat)
        rebuild()
        // Files from before patterns had sections (named parts): each becomes a named pattern of its chords
        let sections = try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent([SequenceSection].self, forKey: .sections) ?? []
        for section in sections.sorted(by: { $0.range.start < $1.range.start }) {
            makePattern(from: section.range, name: section.name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(tempo, forKey: .tempo)
        try container.encode(timeSignature, forKey: .timeSignature)
        try container.encode(lengthInBars, forKey: .lengthInBars)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encode(looseChords, forKey: .chords)
        if !patterns.isEmpty {
            try container.encode(patterns, forKey: .patterns)
            try container.encode(instances, forKey: .patternInstances)
        }
        try container.encodeIfPresent(loopRange, forKey: .loopRange)
        try container.encode(isLooping, forKey: .isLooping)
        try container.encodeIfPresent(audio, forKey: .audio)
        try container.encode(takes, forKey: .takes)
        try container.encodeIfPresent(tablature, forKey: .tablature)
        if tabIsMuted { try container.encode(tabIsMuted, forKey: .tabIsMuted) }
        try container.encode(startBeat, forKey: .startBeat)
        try container.encodeIfPresent(endBeat, forKey: .endBeat)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
