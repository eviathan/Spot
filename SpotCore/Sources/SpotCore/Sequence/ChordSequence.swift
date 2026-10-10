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
public struct ChordRegion: Identifiable, Hashable, Codable, Sendable, BeatRanged {
    public var id: UUID
    public var range: BeatRange
    public var symbol: String
    /// A scale chosen for this chord; nil to use the best suggestion.
    public var scaleId: String?

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

/// How the chords are played back when there's no audio (or alongside it).
public enum BackingStyle: String, Codable, CaseIterable, Sendable {
    case off
    /// Held chords.
    case pad
    /// A strum on every beat.
    case strum
    /// Short stabs on 1 and the "and" of 2.
    case comp
}

/// A song's chords on a beat grid: the contents of a `.spot` file.
public struct ChordSequence: Hashable, Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var tempo: Double
    public var beatsPerBar: Int
    public var lengthInBars: Int
    /// nil to work the key out from the chords.
    public var key: Key?
    /// Kept sorted by start and never overlapping.
    public private(set) var chords: [ChordRegion]
    /// Kept sorted by start and never overlapping.
    public private(set) var sections: [SequenceSection]
    public var loop: BeatRange?
    public var backing: BackingStyle
    /// A recording to play along with, lined up by warp markers.
    public var audio: AudioTrack?
    /// Practice speed: 1 is full tempo, 0.5 half. Slows audio and backing together.
    public var practiceRate: Double

    public init(tempo: Double = 100, beatsPerBar: Int = 4, lengthInBars: Int = 16) {
        self.version = ChordSequence.currentVersion
        self.tempo = tempo
        self.beatsPerBar = beatsPerBar
        self.lengthInBars = lengthInBars
        self.key = nil
        self.chords = []
        self.sections = []
        self.loop = nil
        self.backing = .pad
        self.audio = nil
        self.practiceRate = 1
    }

    public var lengthInBeats: Double {
        Double(lengthInBars * beatsPerBar)
    }

    public func bar(_ index: Int) -> BeatRange {
        BeatRange(Double(index * beatsPerBar), Double((index + 1) * beatsPerBar))
    }

    // MARK: - Reading

    public func chord(at beat: Double) -> ChordRegion? {
        chords.first { $0.range.contains(beat) }
    }

    /// The next chord to start after `beat`.
    public func chord(after beat: Double) -> ChordRegion? {
        chords.first { $0.range.start > beat }
    }

    public func section(at beat: Double) -> SequenceSection? {
        sections.first { $0.range.contains(beat) }
    }

    // MARK: - Editing

    /// Puts a chord over `range`, trimming or splitting whatever was there.
    public mutating func setChord(_ symbol: String, in range: BeatRange, scaleId: String? = nil) {
        let range = clamped(range)
        guard range.length > 0 else { return }
        chords = ChordSequence.carve(chords, removing: range)
        chords.append(ChordRegion(range: range, symbol: symbol, scaleId: scaleId))
        chords.sort { $0.range.start < $1.range.start }
    }

    public mutating func clearChords(in range: BeatRange) {
        chords = ChordSequence.carve(chords, removing: range)
    }

    /// Changes one chord's symbol or scale without moving it.
    public mutating func update(_ id: UUID, symbol: String? = nil, scaleId: String?? = nil) {
        guard let index = chords.firstIndex(where: { $0.id == id }) else { return }
        if let symbol { chords[index].symbol = symbol }
        if let scaleId { chords[index].scaleId = scaleId }
    }

    public mutating func setSection(_ name: String, in range: BeatRange) {
        let range = clamped(range)
        guard range.length > 0 else { return }
        sections = ChordSequence.carve(sections, removing: range)
        sections.append(SequenceSection(name: name, range: range))
        sections.sort { $0.range.start < $1.range.start }
    }

    public mutating func removeSection(_ id: UUID) {
        sections.removeAll { $0.id == id }
    }

    /// Changes the length, dropping or trimming anything past the new end.
    public mutating func setLength(bars: Int) {
        lengthInBars = max(1, bars)
        let end = lengthInBeats
        chords = ChordSequence.carve(chords, removing: BeatRange(end, .infinity))
        sections = ChordSequence.carve(sections, removing: BeatRange(end, .infinity))
        if let loop, loop.start >= end {
            self.loop = nil
        } else if let loop {
            self.loop = BeatRange(loop.start, min(loop.end, end))
        }
    }

    private func clamped(_ range: BeatRange) -> BeatRange {
        BeatRange(max(0, range.start), min(lengthInBeats, range.end))
    }

    /// Removes `removing` from a list of non-overlapping items: trims items at its edges and
    /// splits one that spans it (the second half gets a new id).
    private static func carve<Item: BeatRanged>(_ items: [Item], removing: BeatRange) -> [Item] {
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
        case version, tempo, beatsPerBar, lengthInBars, key, chords, sections, loop, backing, audio, practiceRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version <= ChordSequence.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Made by a newer version of Spot (format \(version))")
        }
        tempo = try container.decode(Double.self, forKey: .tempo)
        beatsPerBar = try container.decode(Int.self, forKey: .beatsPerBar)
        lengthInBars = try container.decode(Int.self, forKey: .lengthInBars)
        key = try container.decodeIfPresent(Key.self, forKey: .key)
        chords = (try container.decodeIfPresent([ChordRegion].self, forKey: .chords) ?? []).sorted { $0.range.start < $1.range.start }
        sections = (try container.decodeIfPresent([SequenceSection].self, forKey: .sections) ?? []).sorted { $0.range.start < $1.range.start }
        loop = try container.decodeIfPresent(BeatRange.self, forKey: .loop)
        backing = try container.decodeIfPresent(BackingStyle.self, forKey: .backing) ?? .pad
        audio = try container.decodeIfPresent(AudioTrack.self, forKey: .audio)
        practiceRate = try container.decodeIfPresent(Double.self, forKey: .practiceRate) ?? 1
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
