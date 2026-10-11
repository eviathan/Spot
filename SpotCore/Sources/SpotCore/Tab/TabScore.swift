//
//  TabScore.swift
//  SpotCore
//

import Foundation

/// A piece in tablature: the contents of a `.spottab` file, and what Guitar Pro files are read into.
///
/// Bars are shared by every track (`masterBars`: time signature, repeats, markers, tempo changes); each
/// track has the same number of bars of its own (`TabTrack.bars`), holding the notes.
public struct TabScore: Hashable, Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var title: String
    public var artist: String
    public var album: String
    /// Quarter notes per minute at the start (bars can change it).
    public var tempo: Double
    public var masterBars: [MasterBar]
    public var tracks: [TabTrack]

    public init(title: String = "", artist: String = "", album: String = "", tempo: Double = 120,
                masterBars: [MasterBar] = [], tracks: [TabTrack] = []) {
        self.version = TabScore.currentVersion
        self.title = title
        self.artist = artist
        self.album = album
        self.tempo = tempo
        self.masterBars = masterBars
        self.tracks = tracks
    }

    /// A new, empty piece: one guitar track and `bars` empty bars of 4/4.
    public static func empty(bars: Int = 8, tuning: Tuning = .standard) -> TabScore {
        var score = TabScore(masterBars: Array(repeating: MasterBar(), count: bars))
        score.tracks = [TabTrack(name: "Guitar", tuning: tuning, barCount: bars)]
        return score
    }

    public var barCount: Int {
        masterBars.count
    }

    /// Adds a bar after `index` (at the end by default), with the same time signature, to every track.
    public mutating func insertBar(after index: Int? = nil) {
        let at = min((index ?? masterBars.count - 1) + 1, masterBars.count)
        var bar = MasterBar()
        if let previous = masterBars.indices.contains(at - 1) ? masterBars[at - 1] : nil {
            bar.timeSignature = previous.timeSignature
            bar.key = previous.key
        }
        masterBars.insert(bar, at: at)
        for track in tracks.indices {
            tracks[track].bars.insert(TabBar(), at: min(at, tracks[track].bars.count))
        }
    }

    public mutating func removeBar(at index: Int) {
        guard masterBars.indices.contains(index), masterBars.count > 1 else { return }
        masterBars.remove(at: index)
        for track in tracks.indices where tracks[track].bars.indices.contains(index) {
            tracks[track].bars.remove(at: index)
        }
    }

    /// Makes every track have exactly one bar per master bar (padding with empty bars or dropping extras).
    public mutating func normalise() {
        for track in tracks.indices {
            let count = tracks[track].bars.count
            if count < masterBars.count {
                tracks[track].bars += Array(repeating: TabBar(), count: masterBars.count - count)
            } else if count > masterBars.count {
                tracks[track].bars.removeLast(count - masterBars.count)
            }
        }
    }

    // MARK: - Files

    enum CodingKeys: String, CodingKey {
        case version, title, artist, album, tempo, masterBars, tracks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version <= TabScore.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Made by a newer version of Spot (format \(version))")
        }
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        tempo = try container.decodeIfPresent(Double.self, forKey: .tempo) ?? 120
        masterBars = try container.decodeIfPresent([MasterBar].self, forKey: .masterBars) ?? []
        tracks = try container.decodeIfPresent([TabTrack].self, forKey: .tracks) ?? []
        normalise()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> TabScore {
        try JSONDecoder().decode(TabScore.self, from: data)
    }
}

public struct TimeSignature: Hashable, Codable, Sendable, CustomStringConvertible {
    public var numerator: Int
    /// 2, 4, 8, 16...
    public var denominator: Int

    public init(_ numerator: Int, _ denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// How long a bar is, in ticks.
    public var ticks: Int {
        TabDuration.ticksPerQuarter * 4 * numerator / max(denominator, 1)
    }

    /// How long a bar is, in quarter notes (3½ for 7/8).
    public var quarterNotes: Double {
        Double(numerator) * 4 / Double(max(denominator, 1))
    }

    /// What it's counted in, in quarter notes (½ for x/8).
    public var countUnit: Double {
        4 / Double(max(denominator, 1))
    }

    /// Time signatures that make sense: 1–32 beats of a whole to a 64th.
    public var isValid: Bool {
        (1...32).contains(numerator) && [1, 2, 4, 8, 16, 32, 64].contains(denominator)
    }

    /// Parses "7/8", "12 / 8".
    public init?(_ text: String) {
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let numerator = Int(parts[0]), let denominator = Int(parts[1]) else { return nil }
        self.init(numerator, denominator)
        guard isValid else { return nil }
    }

    public var description: String {
        "\(numerator)/\(denominator)"
    }
}

/// What every track shares about a bar.
public struct MasterBar: Hashable, Codable, Sendable {
    public var timeSignature: TimeSignature
    /// The key signature from this bar on; nil to carry on with the previous one.
    public var key: Key?
    public var isRepeatStart: Bool
    /// How many times the repeat is played, if a repeat ends here (2 for a plain repeat); 0 if none does.
    public var repeatCount: Int
    /// Which passes play this bar, for 1st/2nd-time endings ([1], [2], [1, 2]...); empty for every pass.
    public var alternateEndings: [Int]
    /// A section name or rehearsal mark ("Verse", "A").
    public var marker: String?
    /// A tempo change at the start of the bar.
    public var tempo: Double?

    public init(timeSignature: TimeSignature = TimeSignature(4, 4), key: Key? = nil, isRepeatStart: Bool = false,
                repeatCount: Int = 0, alternateEndings: [Int] = [], marker: String? = nil, tempo: Double? = nil) {
        self.timeSignature = timeSignature
        self.key = key
        self.isRepeatStart = isRepeatStart
        self.repeatCount = repeatCount
        self.alternateEndings = alternateEndings
        self.marker = marker
        self.tempo = tempo
    }
}

/// One instrument part.
public struct TabTrack: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var tuning: Tuning
    /// The fret the capo is on; 0 for none. Frets are written relative to the capo, as in Guitar Pro.
    public var capo: Int
    /// General MIDI program (25 is a steel-string acoustic guitar, 30 overdriven, 34 a picked bass...).
    public var midiProgram: Int
    public var bars: [TabBar]

    public init(id: UUID = UUID(), name: String, tuning: Tuning = .standard, capo: Int = 0, midiProgram: Int = 25,
                barCount: Int = 0) {
        self.id = id
        self.name = name
        self.tuning = tuning
        self.capo = capo
        self.midiProgram = midiProgram
        self.bars = Array(repeating: TabBar(), count: barCount)
    }

    public var stringCount: Int {
        tuning.strings.count
    }

    /// The MIDI note a fret on a string sounds (capo included).
    public func pitch(string: Int, fret: Int) -> Int {
        tuning.strings[string] + capo + fret
    }
}

public struct TabBar: Hashable, Codable, Sendable {
    /// At least one. A bar with no beats in its first voice is a full-bar rest.
    public var voices: [TabVoice]

    public init(voices: [TabVoice] = [TabVoice()]) {
        self.voices = voices.isEmpty ? [TabVoice()] : voices
    }

    public var isEmpty: Bool {
        voices.allSatisfy { $0.beats.isEmpty }
    }
}

public struct TabVoice: Hashable, Codable, Sendable {
    public var beats: [TabBeat]

    public init(beats: [TabBeat] = []) {
        self.beats = beats
    }

    /// The length of everything in the voice, in ticks.
    public var ticks: Int {
        beats.reduce(0) { $0 + $1.duration.ticks }
    }
}

/// One rhythmic position: a chord of notes (or a rest) with a duration.
public struct TabBeat: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var duration: TabDuration
    /// No notes means a rest.
    public var notes: [TabNote]
    /// A chord name shown above the staff ("Am7").
    public var chord: String?
    /// Free text above the staff.
    public var text: String?
    /// Strummed down (towards the floor) or up.
    public var stroke: Stroke?
    public var tremoloPicking: Bool

    public init(id: UUID = UUID(), duration: TabDuration = TabDuration(.quarter), notes: [TabNote] = [],
                chord: String? = nil, text: String? = nil, stroke: Stroke? = nil, tremoloPicking: Bool = false) {
        self.id = id
        self.duration = duration
        self.notes = notes
        self.chord = chord
        self.text = text
        self.stroke = stroke
        self.tremoloPicking = tremoloPicking
    }

    public var isRest: Bool {
        notes.isEmpty
    }

    public enum Stroke: String, Codable, Sendable {
        case down, up
    }
}

/// A note value, with dots and an optional tuplet (3 in the time of 2, for a triplet).
public struct TabDuration: Hashable, Codable, Sendable {
    public static let ticksPerQuarter = 960

    public enum Value: Int, Codable, CaseIterable, Sendable {
        case whole = 1, half = 2, quarter = 4, eighth = 8, sixteenth = 16, thirtySecond = 32, sixtyFourth = 64
    }

    public var value: Value
    public var dots: Int
    public var tuplet: Tuplet?

    public init(_ value: Value, dots: Int = 0, tuplet: Tuplet? = nil) {
        self.value = value
        self.dots = dots
        self.tuplet = tuplet
    }

    /// e.g. a dotted quarter is 1440, an eighth-note triplet 320.
    public var ticks: Int {
        var ticks = TabDuration.ticksPerQuarter * 4 / value.rawValue
        var add = ticks
        for _ in 0..<max(0, dots) {
            add /= 2
            ticks += add
        }
        if let tuplet {
            ticks = ticks * tuplet.times / max(tuplet.notes, 1)
        }
        return ticks
    }

    public struct Tuplet: Hashable, Codable, Sendable {
        /// How many notes are played...
        public var notes: Int
        /// ...in the time of this many.
        public var times: Int

        public init(_ notes: Int, in times: Int) {
            self.notes = notes
            self.times = times
        }

        public static let triplet = Tuplet(3, in: 2)
    }
}

/// A fretted note and how it's played.
public struct TabNote: Hashable, Codable, Sendable {
    /// 0 is the lowest string (as in `Tuning`).
    public var string: Int
    /// Relative to the capo.
    public var fret: Int
    /// Held on from the previous note on this string (not struck again).
    public var isTied: Bool
    /// Hammered on or pulled off to the next note on this string.
    public var legato: Bool
    public var slide: Slide?
    public var bend: Bend?
    public var vibrato: Bool
    public var palmMute: Bool
    public var letRing: Bool
    /// A muted, percussive "x".
    public var isDead: Bool
    /// Played softly, shown in brackets.
    public var isGhost: Bool
    public var harmonic: Harmonic?
    /// Tapped with the picking hand.
    public var tapped: Bool
    public var accent: Bool

    public init(string: Int, fret: Int, isTied: Bool = false, legato: Bool = false, slide: Slide? = nil, bend: Bend? = nil,
                vibrato: Bool = false, palmMute: Bool = false, letRing: Bool = false, isDead: Bool = false,
                isGhost: Bool = false, harmonic: Harmonic? = nil, tapped: Bool = false, accent: Bool = false) {
        self.string = string
        self.fret = fret
        self.isTied = isTied
        self.legato = legato
        self.slide = slide
        self.bend = bend
        self.vibrato = vibrato
        self.palmMute = palmMute
        self.letRing = letRing
        self.isDead = isDead
        self.isGhost = isGhost
        self.harmonic = harmonic
        self.tapped = tapped
        self.accent = accent
    }

    public enum Slide: String, Codable, CaseIterable, Sendable {
        /// To the next note, striking it again.
        case shift
        /// To the next note without striking it.
        case legato
        case outDownwards, outUpwards, inFromBelow, inFromAbove
    }

    public enum Harmonic: String, Codable, CaseIterable, Sendable {
        case natural, artificial, pinch, tapped, semi
    }

    /// A bend as a curve over the note's length: positions 0...1, values in cents (100 is a half step).
    public struct Bend: Hashable, Codable, Sendable {
        public var points: [Point]

        public init(points: [Point]) {
            self.points = points.sorted { $0.position < $1.position }
        }

        /// Up by `cents` and held (a full bend is 200).
        public static func up(_ cents: Int) -> Bend {
            Bend(points: [Point(position: 0, cents: 0), Point(position: 0.5, cents: cents), Point(position: 1, cents: cents)])
        }

        /// Up by `cents` and back down.
        public static func upAndRelease(_ cents: Int) -> Bend {
            Bend(points: [Point(position: 0, cents: 0), Point(position: 0.33, cents: cents),
                          Point(position: 0.66, cents: cents), Point(position: 1, cents: 0)])
        }

        /// Already bent up by `cents` when struck, then released.
        public static func prebendRelease(_ cents: Int) -> Bend {
            Bend(points: [Point(position: 0, cents: cents), Point(position: 0.5, cents: 0), Point(position: 1, cents: 0)])
        }

        /// The highest point, e.g. 200 for a full bend.
        public var peak: Int {
            points.map(\.cents).max() ?? 0
        }

        public struct Point: Hashable, Codable, Sendable {
            public var position: Double
            public var cents: Int

            public init(position: Double, cents: Int) {
                self.position = position
                self.cents = cents
            }
        }
    }
}
