//
//  GuitarProBinary.swift
//  SpotCore
//

import Foundation

/// Guitar Pro 3, 4 and 5 files (`.gp3`, `.gp4`, `.gp5`): little-endian binary, read field by field (nothing
/// says how long anything is, so every field has to be read or skipped in order, the way each version wrote it).
enum GuitarProBinary {
    static func read(_ data: Data) throws -> GuitarPro.Import {
        try readCounting(data).import
    }

    /// Also how much of the file was read (all of it, if the format was followed exactly).
    static func readCounting(_ data: Data) throws -> (import: GuitarPro.Import, read: Int) {
        var reader = Reader(bytes: [UInt8](data))
        do {
            let read = try reader.readSong()
            return (read, reader.at)
        } catch let error as GuitarPro.Error {
            throw error
        } catch {
            throw GuitarPro.Error.damaged("it ends too soon")
        }
    }

    /// Ran past the end of the file.
    struct EndOfFile: Error {}

    private struct Header {
        var timeSignature = TimeSignature(4, 4)
        var isRepeatStart = false
        /// Plays, if a repeat ends here.
        var repeatCount = 0
        /// Bit n set for the (n + 1)th ending.
        var alternateEndings = 0
        var marker: String?
        var key: (accidentals: Int, minor: Bool)?
    }

    private struct TrackInfo {
        var name: String
        var isDrums: Bool
        /// Lowest string first.
        var tuning: [Int]
        var capo: Int
        var program: Int
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0
        /// 300, 400, 406, 500, 510...
        var version = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        // MARK: Song

        mutating func readSong() throws -> GuitarPro.Import {
            let versionText = try byteSizeString(30)
            // "FICHIER GUITAR PRO v5.10"
            guard let range = versionText.range(of: #"v\d\.\d\d"#, options: .regularExpression),
                  let major = Int(versionText[range].dropFirst().prefix(1)), let minor = Int(versionText[range].suffix(2)) else {
                throw GuitarPro.Error.notGuitarPro
            }
            version = major * 100 + minor
            guard (300..<600).contains(version) else { throw GuitarPro.Error.unsupported("Guitar Pro \(major)") }

            var score = TabScore()
            score.title = try intByteSizeString()
            _ = try intByteSizeString()                       // subtitle
            score.artist = try intByteSizeString()
            score.album = try intByteSizeString()
            _ = try intByteSizeString()                       // words
            if version >= 500 { _ = try intByteSizeString() } // music
            _ = try intByteSizeString()                       // copyright
            _ = try intByteSizeString()                       // tabbed by
            _ = try intByteSizeString()                       // instructions
            for _ in 0..<max(try int(), 0) { _ = try intByteSizeString() } // notice lines

            if version < 500 { _ = try bool() }               // triplet feel
            if version >= 400 {                               // lyrics
                _ = try int()
                for _ in 0..<5 {
                    _ = try int()
                    _ = try intSizeString()
                }
            }
            if version >= 510 { try skip(19) }                // master effect
            if version >= 500 {                               // page setup, tempo name
                try skip(30)
                for _ in 0..<10 { _ = try intByteSizeString() }
                _ = try intByteSizeString()
            }
            score.tempo = Double(max(try int(), 1))
            if version >= 510 { _ = try bool() }              // hide tempo
            let songKey = Int(Int8(truncatingIfNeeded: try int()))
            if version >= 400 { try skip(1) }                 // octave

            var programs: [Int] = []                          // 64 MIDI channels
            for _ in 0..<64 {
                programs.append(try int())
                try skip(8)
            }
            if version >= 500 { try skip(38 + 4) }            // directions (coda, segno...), master reverb

            let barCount = try int(), trackCount = try int()
            guard (0...10_000).contains(barCount), (0...128).contains(trackCount) else { throw GuitarPro.Error.damaged("odd sizes") }

            var headers: [Header] = []
            for index in 0..<barCount {
                headers.append(try readHeader(index: index, previous: headers.last, all: headers))
            }
            var tracks: [TrackInfo] = []
            for index in 0..<trackCount {
                tracks.append(try readTrack(index: index, programs: programs))
            }
            if version >= 500 { try skip(version == 500 ? 2 : 1) }

            // Bars, track by track within each bar
            var bars = Array(repeating: [TabBar](), count: trackCount)
            var tempos: [Int: Double] = [:]
            var lastFrets = Array(repeating: [Int: Int](), count: trackCount)
            for bar in 0..<barCount {
                for track in 0..<trackCount {
                    var voices: [TabVoice] = []
                    for _ in 0..<(version >= 500 ? 2 : 1) {
                        let beatCount = try int()
                        guard (0...1024).contains(beatCount) else { throw GuitarPro.Error.damaged("odd beat count") }
                        var voice = TabVoice()
                        for _ in 0..<beatCount {
                            let (beat, tempo) = try readBeat(track: tracks[track], lastFrets: &lastFrets[track])
                            // An "empty" beat only holds the place of a voice with nothing in it
                            if let beat { voice.beats.append(beat) }
                            if let tempo, tempos[bar] == nil { tempos[bar] = tempo }
                        }
                        voices.append(voice)
                    }
                    if version >= 500 && at < bytes.count { try skip(1) } // line break (missing after the very last bar)
                    // Keep the second voice only if it has something in it
                    bars[track].append(TabBar(voices: voices.enumerated().filter { $0.offset == 0 || !$0.element.beats.isEmpty }.map(\.element)))
                }
            }

            // Into the model
            var previousKey: Key? = Key(conventional: PitchClass(0), .major)
            var tempo = score.tempo
            for (index, header) in headers.enumerated() {
                var bar = MasterBar(timeSignature: header.timeSignature, isRepeatStart: header.isRepeatStart,
                                    repeatCount: header.repeatCount,
                                    alternateEndings: (0..<8).filter { header.alternateEndings & (1 << $0) != 0 }.map { $0 + 1 },
                                    marker: header.marker)
                let key = header.key ?? (index == 0 ? (min(max(songKey, -7), 7), false) : nil)
                if let key {
                    let read = GPIF.key(accidentals: min(max(key.accidentals, -7), 7), minor: key.minor)
                    if read != previousKey {
                        bar.key = read
                        previousKey = read
                    }
                }
                if let change = tempos[index], change != tempo {
                    if index == 0 { score.tempo = change } else { bar.tempo = change }
                    tempo = change
                }
                score.masterBars.append(bar)
            }
            var skipped: [String] = []
            for (index, info) in tracks.enumerated() {
                if info.isDrums || info.tuning.isEmpty {
                    skipped.append(info.name)
                    continue
                }
                let tuning = Tuning.presets.first { $0.strings == info.tuning }
                    ?? Tuning(id: "custom", name: info.tuning.map(Tuning.noteName).joined(separator: " "), strings: info.tuning)
                var track = TabTrack(name: info.name.isEmpty ? "Track \(index + 1)" : info.name, tuning: tuning,
                                     capo: info.capo, midiProgram: info.program)
                track.bars = bars[index]
                score.tracks.append(track)
            }
            if score.masterBars.isEmpty {
                score.masterBars = [MasterBar()]
            }
            score.normalise()
            return GuitarPro.Import(score: score, skippedTracks: skipped)
        }

        private mutating func readHeader(index: Int, previous: Header?, all: [Header]) throws -> Header {
            if version >= 500 && index > 0 { try skip(1) }
            let flags = try u8()
            var header = Header()
            header.timeSignature = previous?.timeSignature ?? TimeSignature(4, 4)
            if flags & 0x01 != 0 { header.timeSignature.numerator = max(try i8(), 1) }
            if flags & 0x02 != 0 { header.timeSignature.denominator = max(try i8(), 1) }
            header.isRepeatStart = flags & 0x04 != 0
            if flags & 0x08 != 0 {
                // Guitar Pro 5 stores the plays, earlier versions the repeats
                header.repeatCount = max(try i8() + (version >= 500 ? 0 : 1), 2)
            }
            if version < 500 {
                if flags & 0x10 != 0 {
                    // The ending's number; it takes whichever earlier endings since the repeat began haven't been used
                    let number = try u8()
                    var used = 0
                    for earlier in all.reversed() {
                        if earlier.isRepeatStart { break }
                        used |= earlier.alternateEndings
                    }
                    header.alternateEndings = ((1 << min(number, 8)) - 1) & ~used
                }
                if flags & 0x20 != 0 { header.marker = try readMarker() }
                if flags & 0x40 != 0 { header.key = (try i8(), try i8() == 1) }
            } else {
                if flags & 0x20 != 0 { header.marker = try readMarker() }
                if flags & 0x10 != 0 { header.alternateEndings = try u8() }
                if flags & 0x40 != 0 { header.key = (try i8(), try i8() == 1) }
                if flags & 0x03 != 0 { try skip(4) }          // beaming
                if flags & 0x10 == 0 { try skip(1) }
                try skip(1)                                   // triplet feel
            }
            return header
        }

        private mutating func readMarker() throws -> String? {
            let name = try intByteSizeString()
            try skip(4)                                       // colour
            return name.isEmpty ? nil : name
        }

        private mutating func readTrack(index: Int, programs: [Int]) throws -> TrackInfo {
            if version >= 500 && (index == 0 || version == 500) { try skip(1) }
            let flags = try u8()
            let name = try byteSizeString(40)
            let stringCount = try int()
            var strings: [Int] = []
            for string in 0..<7 {
                let pitch = try int()
                if string < stringCount { strings.append(pitch) }
            }
            _ = try int()                                     // port
            let channel = try int() - 1
            _ = try int()                                     // effects channel
            _ = try int()                                     // frets
            let capo = try int()
            try skip(4)                                       // colour
            if version >= 500 {
                try skip(version >= 510 ? 49 : 44)            // settings and RSE
                if version >= 510 {
                    _ = try intByteSizeString()
                    _ = try intByteSizeString()
                }
            }
            return TrackInfo(name: name, isDrums: flags & 0x01 != 0,
                             tuning: strings.reversed().filter { $0 > 0 },
                             capo: max(capo, 0),
                             program: programs.indices.contains(channel) ? min(max(programs[channel], 0), 127) : 25)
        }

        // MARK: Beats and notes

        /// A beat (nil for an "empty" one, which stands for nothing), and a tempo change if the beat has one.
        private mutating func readBeat(track: TrackInfo, lastFrets: inout [Int: Int]) throws -> (TabBeat?, Double?) {
            let flags = try u8()
            var isEmpty = false
            if flags & 0x40 != 0 { isEmpty = try u8() == 0 }  // 0 empty, 2 rest
            let values: [Int: TabDuration.Value] = [-2: .whole, -1: .half, 0: .quarter, 1: .eighth, 2: .sixteenth,
                                                    3: .thirtySecond, 4: .sixtyFourth]
            var beat = TabBeat(duration: TabDuration(values[try i8()] ?? .quarter, dots: flags & 0x01 != 0 ? 1 : 0))
            if flags & 0x20 != 0 {
                let tuplets: [Int: TabDuration.Tuplet] = [3: .triplet, 5: .init(5, in: 4), 6: .init(6, in: 4), 7: .init(7, in: 4),
                                                          9: .init(9, in: 8), 10: .init(10, in: 8), 11: .init(11, in: 8),
                                                          12: .init(12, in: 8), 13: .init(13, in: 8)]
                beat.duration.tuplet = tuplets[try int()]
            }
            if flags & 0x02 != 0 { beat.chord = try readChord(stringCount: track.tuning.count) }
            if flags & 0x04 != 0 {
                let text = try intByteSizeString()
                beat.text = text.isEmpty ? nil : text
            }
            var effects = BeatEffects()
            if flags & 0x08 != 0 { effects = try readBeatEffects() }
            beat.stroke = effects.stroke
            var tempo: Double?
            if flags & 0x10 != 0 { tempo = try readMixTable() }

            let stringFlags = try u8()
            let stringCount = track.tuning.count
            for number in 1...7 where stringFlags & (1 << (7 - number)) != 0 {
                // Strings are numbered from the highest, 1
                let read = try readNote(lastFrets: &lastFrets, string: stringCount - number, beat: &beat)
                guard number <= stringCount, var note = read else { continue }
                if effects.vibrato { note.vibrato = true }
                if effects.tapped { note.tapped = true }
                if let harmonic = effects.harmonic { note.harmonic = harmonic }
                beat.notes.append(note)
            }
            beat.notes.sort { $0.string < $1.string }

            if version >= 500 {
                let flags2 = try i16()
                if flags2 & 0x0800 != 0 { try skip(1) }       // beaming break
            }
            return (isEmpty ? nil : beat, tempo)
        }

        private struct BeatEffects {
            var vibrato = false
            var tapped = false
            var harmonic: TabNote.Harmonic?
            var stroke: TabBeat.Stroke?
        }

        private mutating func readBeatEffects() throws -> BeatEffects {
            var effects = BeatEffects()
            let flags = try u8()
            let flags2 = version >= 400 ? try u8() : 0
            effects.vibrato = flags & 0x03 != 0
            if flags & 0x20 != 0 {
                let slap = try i8()                           // 1 tap, 2 slap, 3 pop
                effects.tapped = slap == 1
                if version < 400 { try skip(4) }              // tremolo bar
            }
            if version < 400 {
                if flags & 0x04 != 0 { effects.harmonic = .natural }
                if flags & 0x08 != 0 { effects.harmonic = .artificial }
            }
            if flags2 & 0x04 != 0 { _ = try readBend() }      // tremolo bar
            if flags & 0x40 != 0 {
                // Strum speeds; Guitar Pro 5 has up first
                let first = try i8(), second = try i8()
                let (down, up) = version >= 500 ? (second, first) : (first, second)
                effects.stroke = up > 0 ? .up : down > 0 ? .down : nil
            }
            if flags2 & 0x02 != 0 { try skip(1) }             // pick stroke
            return effects
        }

        /// Skips a mix table change, returning its tempo if it sets one.
        private mutating func readMixTable() throws -> Double? {
            _ = try i8()                                      // instrument
            if version >= 500 { try skip(16) }                // RSE
            let levels = try (0..<6).map { _ in try i8() }    // volume, balance, chorus, reverb, phaser, tremolo
            if version >= 500 { _ = try intByteSizeString() } // tempo name
            let tempo = try int()
            for level in levels where level >= 0 { try skip(1) } // transition times
            if tempo >= 0 {
                try skip(1)
                if version >= 510 { try skip(1) }
            }
            if version >= 400 { try skip(1) }                 // applies to all tracks
            if version >= 500 { try skip(1) }
            if version >= 510 {
                _ = try intByteSizeString()
                _ = try intByteSizeString()
            }
            return tempo > 0 ? Double(tempo) : nil
        }

        private mutating func readChord(stringCount: Int) throws -> String? {
            var name: String
            if version >= 500 {
                try skip(17)
                name = try byteSizeString(21)
                try skip(4 + 4 + 28 + 1 + 5 + 26)
            } else if try u8() != 0 {
                if version >= 400 {
                    try skip(16)
                    name = try byteSizeString(21)
                    try skip(4 + 4 + 28 + 1 + 5 + 26)
                } else {
                    try skip(25)
                    name = try byteSizeString(34)
                    try skip(4 + 24 + 36)
                }
            } else {
                name = try intByteSizeString()
                if try int() > 0 {                            // first fret, then the frets
                    try skip(4 * (version >= 406 ? 7 : 6))
                }
            }
            // A name too long for its field runs on into the bytes after it
            name = String(name.prefix { $0 != "\0" }).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }

        /// A note on `string` (0 the lowest), or nil if it's not on a string the track has.
        private mutating func readNote(lastFrets: inout [Int: Int], string: Int, beat: inout TabBeat) throws -> TabNote? {
            let flags = try u8()
            var note = TabNote(string: max(string, 0), fret: 0)
            note.accent = flags & 0x42 != 0
            note.isGhost = flags & 0x04 != 0
            var type = 1
            if flags & 0x20 != 0 { type = try u8() }          // 1 normal, 2 tied, 3 dead
            if flags & 0x01 != 0 && version < 500 { try skip(2) } // its own duration and tuplet
            if flags & 0x10 != 0 { try skip(1) }              // dynamic
            if flags & 0x20 != 0 { note.fret = max(try i8(), 0) }
            if flags & 0x80 != 0 { try skip(2) }              // fingering
            if version >= 500 {
                if flags & 0x01 != 0 { try skip(8) }          // duration percent
                try skip(1)
            }
            if type == 2 {
                note.isTied = true
                note.fret = lastFrets[string] ?? note.fret
            }
            note.isDead = type == 3
            if flags & 0x08 != 0 { try readNoteEffects(&note, beat: &beat) }
            guard string >= 0 else { return nil }
            lastFrets[string] = note.fret
            return note
        }

        private mutating func readNoteEffects(_ note: inout TabNote, beat: inout TabBeat) throws {
            let flags = try u8()
            let flags2 = version >= 400 ? try u8() : 0
            if flags & 0x01 != 0 { note.bend = try readBend() }
            note.legato = flags & 0x02 != 0
            if version < 400 && flags & 0x04 != 0 { note.slide = .shift }
            note.letRing = flags & 0x08 != 0
            if flags & 0x10 != 0 { try skip(version >= 500 ? 5 : 4) } // grace note (not kept)
            guard version >= 400 else { return }
            note.palmMute = flags2 & 0x02 != 0
            if flags2 & 0x04 != 0 {
                try skip(1)
                beat.tremoloPicking = true
            }
            if flags2 & 0x08 != 0 {
                if version >= 500 {
                    let slides: [(Int, TabNote.Slide)] = [(1, .shift), (2, .legato), (4, .outDownwards), (8, .outUpwards),
                                                          (16, .inFromBelow), (32, .inFromAbove)]
                    let bits = try u8()
                    note.slide = slides.first { bits & $0.0 != 0 }?.1
                } else {
                    let slides: [Int: TabNote.Slide] = [1: .shift, 2: .legato, 3: .outDownwards, 4: .outUpwards,
                                                        -1: .inFromBelow, -2: .inFromAbove]
                    note.slide = slides[try i8()]
                }
            }
            if flags2 & 0x10 != 0 {
                let type = try i8()
                switch type {
                case 1: note.harmonic = .natural
                case 2:
                    note.harmonic = .artificial
                    if version >= 500 { try skip(3) }
                case 3:
                    note.harmonic = .tapped
                    if version >= 500 { try skip(1) }
                case 4: note.harmonic = .pinch
                case 5: note.harmonic = .semi
                case 15, 17, 22: note.harmonic = .artificial
                default: break
                }
            }
            if flags2 & 0x20 != 0 { try skip(2) }             // trill
            if flags2 & 0x40 != 0 { note.vibrato = true }
        }

        /// A bend: points along the note (0–60) with values in quarter tones × 25.
        private mutating func readBend() throws -> TabNote.Bend? {
            try skip(1)                                       // type
            _ = try int()                                     // value
            let count = try int()
            guard (0...64).contains(count) else { throw GuitarPro.Error.damaged("odd bend") }
            var points: [TabNote.Bend.Point] = []
            for _ in 0..<count {
                let position = try int(), value = try int()
                _ = try bool()                                // vibrato
                points.append(TabNote.Bend.Point(position: min(max(Double(position) / 60, 0), 1), cents: value * 2))
            }
            return points.contains { $0.cents != 0 } ? TabNote.Bend(points: points) : nil
        }

        // MARK: Primitives

        mutating func skip(_ count: Int) throws {
            guard count >= 0, at + count <= bytes.count else { throw EndOfFile() }
            at += count
        }

        mutating func u8() throws -> Int {
            guard at < bytes.count else { throw EndOfFile() }
            defer { at += 1 }
            return Int(bytes[at])
        }

        mutating func i8() throws -> Int {
            Int(Int8(bitPattern: UInt8(try u8())))
        }

        mutating func bool() throws -> Bool {
            try u8() != 0
        }

        mutating func i16() throws -> Int {
            let low = try u8(), high = try u8()
            return Int(Int16(bitPattern: UInt16(low | high << 8)))
        }

        mutating func int() throws -> Int {
            guard at + 4 <= bytes.count else { throw EndOfFile() }
            defer { at += 4 }
            let value = UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
            return Int(Int32(bitPattern: value))
        }

        /// `count` bytes as text (Windows Latin 1, as Guitar Pro wrote it).
        mutating func text(_ count: Int) throws -> String {
            guard count >= 0, at + count <= bytes.count else { throw EndOfFile() }
            defer { at += count }
            let slice = Data(bytes[at..<(at + count)])
            return String(data: slice, encoding: .windowsCP1252) ?? String(decoding: slice, as: UTF8.self)
        }

        /// A length byte, then `size` bytes of which that many are the text (trimmed).
        mutating func byteSizeString(_ size: Int) throws -> String {
            let length = try u8()
            let start = at
            let value = try text(min(length, size))
            at = start
            try skip(size)
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// A 4-byte length, then the text.
        mutating func intSizeString() throws -> String {
            let length = try int()
            guard (0...1_000_000).contains(length) else { throw GuitarPro.Error.damaged("odd text") }
            return try text(length)
        }

        /// A 4-byte size (length + 1), a length byte, then the text (trimmed: names often end in spaces).
        mutating func intByteSizeString() throws -> String {
            let size = try int() - 1
            guard (-1...1_000_000).contains(size) else { throw GuitarPro.Error.damaged("odd text") }
            if size < 0 { return "" }
            let length = try u8()
            let start = at
            let value = try text(min(length, size))
            at = start
            try skip(size)
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
