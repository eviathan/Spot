//
//  GuitarPro.swift
//  SpotCore
//

import Foundation

/// Reading Guitar Pro files into a `TabScore`, and writing one out as Guitar Pro 7.
///
/// Guitar Pro 7 and 8 files (`.gp`) are zip archives holding the score as XML (`Content/score.gpif`, "GPIF").
/// Guitar Pro 6 (`.gpx`) keeps the same XML in its own container; 3, 4 and 5 are binary (`GuitarProBinary`).
public enum GuitarPro {
    public enum Error: LocalizedError {
        case notGuitarPro
        case unsupported(String)
        case damaged(String)

        public var errorDescription: String? {
            switch self {
            case .notGuitarPro: return "This isn't a Guitar Pro file."
            case .unsupported(let what): return "\(what) files can't be opened yet."
            case .damaged(let why): return "The Guitar Pro file looks damaged (\(why))."
            }
        }
    }

    /// What was read, and anything that had to be left behind.
    public struct Import {
        public var score: TabScore
        /// Tracks that weren't brought in (drum kits, which have no strings to tab).
        public var skippedTracks: [String]
    }

    /// The file name extensions Guitar Pro uses.
    public static let fileExtensions = ["gp", "gpx", "gp5", "gp4", "gp3"]

    /// Reads any Guitar Pro file, telling the version from its contents.
    public static func read(_ data: Data) throws -> Import {
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return try readGP7(data)
        }
        if data.starts(with: Array("BCF".utf8)) {
            throw Error.unsupported("Guitar Pro 6")
        }
        if data.count > 1, String(decoding: data.dropFirst().prefix(18), as: UTF8.self).hasPrefix("FICHIER GUITAR PRO") {
            return try GuitarProBinary.read(data)
        }
        throw Error.notGuitarPro
    }

    /// A Guitar Pro 7 or 8 file (a zip with the score as GPIF).
    public static func readGP7(_ data: Data) throws -> Import {
        let files: [String: Data]
        do {
            files = try Zip.entries(of: data)
        } catch {
            throw Error.damaged("it can't be unzipped")
        }
        guard let gpif = files["Content/score.gpif"] else { throw Error.notGuitarPro }
        return try GPIF.read(gpif)
    }

    /// The score as a Guitar Pro 7 file (which Guitar Pro 8 opens too).
    public static func gp7(_ score: TabScore) -> Data {
        let gpif = GPIF.write(score)
        // Which staves each view shows: the whole score, then each track on its own (3 = standard notation and tab)
        var parts = Data()
        parts.append(bigEndian: UInt32(score.tracks.count + 1))
        for view in 0...score.tracks.count {
            parts.append(0)                                         // not multi-rhythm
            let groups = view == 0 ? score.tracks.count : 1
            parts.append(bigEndian: UInt32(groups))
            parts.append(contentsOf: Array(repeating: UInt8(3), count: groups))
        }
        parts.append(bigEndian: 1)
        return Zip.archive([
            ("VERSION", Data("7.0".utf8)),
            ("meta.json", Data("{\n}\n".utf8)),
            ("Content/score.gpif", gpif),
            ("Content/PartConfiguration", parts),
        ])
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}

// MARK: - GPIF

/// Guitar Pro's score XML (Guitar Pro 6, 7 and 8). Everything is in flat lists cross-referenced by id: master bars
/// list a bar per track, bars list voices, voices list beats, beats list notes and refer to a rhythm. Beats and
/// notes can be shared (a voice can list the same beat twice).
enum GPIF {
    // MARK: Reading

    static func read(_ data: Data) throws -> GuitarPro.Import {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data)
        } catch {
            throw GuitarPro.Error.damaged("the score can't be read")
        }
        guard let root = document.rootElement(), root.name == "GPIF" else { throw GuitarPro.Error.notGuitarPro }
        return Reader(root: root).read()
    }

    private struct Reader {
        let root: XMLElement
        let rhythms: [Int: XMLElement]
        let notes: [Int: XMLElement]
        let beats: [Int: XMLElement]
        let voices: [Int: XMLElement]
        let bars: [Int: XMLElement]

        init(root: XMLElement) {
            self.root = root
            func byID(_ list: String, _ item: String) -> [Int: XMLElement] {
                var result: [Int: XMLElement] = [:]
                for element in root.child(list)?.elements(forName: item) ?? [] {
                    if let id = element.attribute("id").flatMap(Int.init) {
                        result[id] = element
                    }
                }
                return result
            }
            rhythms = byID("Rhythms", "Rhythm")
            notes = byID("Notes", "Note")
            beats = byID("Beats", "Beat")
            voices = byID("Voices", "Voice")
            bars = byID("Bars", "Bar")
        }

        func read() -> GuitarPro.Import {
            var score = TabScore()
            if let info = root.child("Score") {
                score.title = info.text("Title") ?? ""
                score.artist = info.text("Artist") ?? ""
                score.album = info.text("Album") ?? ""
            }

            // Tracks (drum kits have nothing to put on strings)
            struct Kept { var index: Int; var track: TabTrack; var chords: [Int: String] }
            var kept: [Kept] = []
            var skipped: [String] = []
            for (index, element) in (root.child("Tracks")?.elements(forName: "Track") ?? []).enumerated() {
                let name = element.text("Name") ?? "Track \(index + 1)"
                // Guitar Pro 7 keeps string settings on the staff, 6 on the track
                let staff = element.child("Staves")?.elements(forName: "Staff").first
                func property(_ name: String) -> XMLElement? {
                    staff?.property(name) ?? element.property(name)
                }
                let pitches = property("Tuning")?.text("Pitches").map(GPIF.numbers) ?? []
                let instrument = element.text("InstrumentSet/Type") ?? ""
                if element.child("NotationPatch") != nil || instrument.lowercased().contains("drum")
                    || pitches.isEmpty || pitches.allSatisfy({ $0 == 0 }) {
                    skipped.append(name)
                    continue
                }
                let tuning = Tuning.presets.first { $0.strings == pitches }
                    ?? Tuning(id: "custom", name: pitches.map(Tuning.noteName).joined(separator: " "), strings: pitches)
                let capo = property("CapoFret")?.text("Fret").flatMap(Int.init) ?? 0
                let program = (element.text("Sounds/Sound/MIDI/Program") ?? element.text("GeneralMidi/Program")).flatMap(Int.init) ?? 25
                var chords: [Int: String] = [:]
                for collection in ["ChordCollection", "DiagramCollection"] {
                    for item in property(collection)?.child("Items")?.elements(forName: "Item") ?? [] {
                        if let id = item.attribute("id").flatMap(Int.init), let chord = item.attribute("name"), !chord.isEmpty {
                            chords[id] = chord
                        }
                    }
                }
                kept.append(Kept(index: index, track: TabTrack(name: name, tuning: tuning, capo: capo, midiProgram: program), chords: chords))
            }

            // Bars
            // C major is what a bar with no key means
            var previousKey: Key? = Key(conventional: PitchClass(0), .major)
            for element in root.child("MasterBars")?.elements(forName: "MasterBar") ?? [] {
                var bar = MasterBar()
                if let time = element.text("Time")?.split(separator: "/"), time.count == 2,
                   let numerator = Int(time[0]), let denominator = Int(time[1]) {
                    bar.timeSignature = TimeSignature(numerator, denominator)
                }
                if let key = element.child("Key"), let count = key.text("AccidentalCount").flatMap(Int.init) {
                    let read = GPIF.key(accidentals: count, minor: key.text("Mode") == "Minor")
                    if read != previousKey {
                        bar.key = read
                        previousKey = read
                    }
                }
                if let repeatElement = element.child("Repeat") {
                    bar.isRepeatStart = repeatElement.attribute("start") == "true"
                    if repeatElement.attribute("end") == "true" {
                        bar.repeatCount = max(repeatElement.attribute("count").flatMap(Int.init) ?? 2, 2)
                    }
                }
                bar.alternateEndings = element.text("AlternateEndings").map(GPIF.numbers) ?? []
                if let section = element.child("Section") {
                    bar.marker = section.text("Text") ?? section.text("Letter")
                }
                score.masterBars.append(bar)

                let barIDs = element.text("Bars").map(GPIF.numbers) ?? []
                for track in kept.indices {
                    let id = barIDs.indices.contains(kept[track].index) ? barIDs[kept[track].index] : -1
                    let read = self.bar(id, track: kept[track].track, chords: kept[track].chords)
                    kept[track].track.bars.append(read)
                }
            }

            // Tempo changes (in the master track's automations)
            for automation in root.child("MasterTrack")?.child("Automations")?.elements(forName: "Automation") ?? [] {
                guard automation.text("Type") == "Tempo", let value = automation.text("Value") else { continue }
                let parts = value.split(separator: " ").compactMap { Double($0) }
                guard let bpm = parts.first, bpm > 0 else { continue }
                let tempo = bpm * GPIF.quarters(perTempoUnit: parts.count > 1 ? Int(parts[1]) : 2)
                let bar = automation.text("Bar").flatMap(Int.init) ?? 0
                if bar == 0 {
                    score.tempo = tempo
                } else if score.masterBars.indices.contains(bar) {
                    score.masterBars[bar].tempo = tempo
                }
            }

            score.tracks = kept.map(\.track)
            if score.masterBars.isEmpty {
                score.masterBars = [MasterBar()]
            }
            score.normalise()
            return GuitarPro.Import(score: score, skippedTracks: skipped)
        }

        private func bar(_ id: Int, track: TabTrack, chords: [Int: String]) -> TabBar {
            guard let element = bars[id] else { return TabBar() }
            let voiceIDs = element.text("Voices").map(GPIF.numbers) ?? []
            let read = voiceIDs.filter { $0 >= 0 }.compactMap { voices[$0] }.map { voice in
                TabVoice(beats: (voice.text("Beats").map(GPIF.numbers) ?? []).compactMap { beat($0, track: track, chords: chords) })
            }
            return TabBar(voices: read)
        }

        private func beat(_ id: Int, track: TabTrack, chords: [Int: String]) -> TabBeat? {
            guard let element = beats[id] else { return nil }
            // Grace notes don't take up time in the bar, which the model has no way to say
            if element.child("GraceNotes") != nil { return nil }
            var beat = TabBeat(duration: duration(element.child("Rhythm")?.attribute("ref").flatMap(Int.init)))
            beat.notes = (element.text("Notes").map(GPIF.numbers) ?? [])
                .compactMap { note($0, track: track) }
                .reduce(into: [TabNote]()) { notes, note in
                    if !notes.contains(where: { $0.string == note.string }) { notes.append(note) }
                }
                .sorted { $0.string < $1.string }
            beat.text = element.text("FreeText")
            beat.chord = element.text("Chord").flatMap(Int.init).flatMap { chords[$0] }
            switch element.property("Brush")?.text("Direction") {
            case "Down": beat.stroke = .down
            case "Up": beat.stroke = .up
            default: break
            }
            beat.tremoloPicking = element.child("Tremolo") != nil
            return beat
        }

        private func duration(_ id: Int?) -> TabDuration {
            guard let id, let rhythm = rhythms[id] else { return TabDuration(.quarter) }
            let values: [String: TabDuration.Value] = [
                "Whole": .whole, "Half": .half, "Quarter": .quarter, "Eighth": .eighth, "16th": .sixteenth,
                "32nd": .thirtySecond, "64th": .sixtyFourth, "128th": .sixtyFourth, "256th": .sixtyFourth,
            ]
            var duration = TabDuration(values[rhythm.text("NoteValue") ?? ""] ?? .quarter)
            duration.dots = rhythm.child("AugmentationDot")?.attribute("count").flatMap(Int.init) ?? 0
            if let tuplet = rhythm.child("PrimaryTuplet"),
               let notes = tuplet.attribute("num").flatMap(Int.init), let times = tuplet.attribute("den").flatMap(Int.init),
               notes > 0, times > 0, notes != times {
                duration.tuplet = TabDuration.Tuplet(notes, in: times)
            }
            return duration
        }

        private func note(_ id: Int, track: TabTrack) -> TabNote? {
            guard let element = notes[id] else { return nil }
            func flag(_ name: String) -> Bool { element.property(name) != nil }
            func float(_ name: String) -> Double? { element.property(name)?.text("Float").flatMap(Double.init) }

            var string = element.property("String")?.text("String").flatMap(Int.init)
            var fret = element.property("Fret")?.text("Fret").flatMap(Int.init)
            // Notes from a part without frets: put them on the highest string they reach
            if string == nil || fret == nil, let midi = element.property("Midi")?.text("Number").flatMap(Int.init) {
                for candidate in (0..<track.stringCount).reversed() {
                    let candidateFret = midi - track.tuning.strings[candidate] - track.capo
                    if (0...24).contains(candidateFret) {
                        string = candidate
                        fret = candidateFret
                        break
                    }
                }
            }
            guard let string, let fret, string >= 0, string < track.stringCount, fret >= 0 else { return nil }

            var note = TabNote(string: string, fret: fret)
            note.isTied = element.child("Tie")?.attribute("destination") == "true"
            note.legato = flag("HopoOrigin")
            if let flags = element.property("Slide")?.text("Flags").flatMap(Int.init) {
                let slides: [(Int, TabNote.Slide)] = [(1, .shift), (2, .legato), (4, .outDownwards), (8, .outUpwards),
                                                      (16, .inFromBelow), (32, .inFromAbove)]
                note.slide = slides.first { flags & $0.0 != 0 }?.1
            }
            if flag("Bended") {
                // Values are in quarter tones × 25 (100 is a whole step), offsets 0–100 along the note
                let origin = float("BendOriginValue") ?? 0
                let middle = float("BendMiddleValue")
                let destination = float("BendDestinationValue") ?? middle ?? origin
                var points = [(float("BendOriginOffset") ?? 0, origin)]
                if let middle {
                    let first = float("BendMiddleOffset1"), second = float("BendMiddleOffset2")
                    if first == nil && second == nil { points.append((50, middle)) }
                    if let first { points.append((first, middle)) }
                    if let second, second != first { points.append((second, middle)) }
                }
                points.append((float("BendDestinationOffset") ?? 100, destination))
                let bend = TabNote.Bend(points: points.map {
                    TabNote.Bend.Point(position: min(max($0.0 / 100, 0), 1), cents: Int(($0.1 * 2).rounded()))
                })
                if bend.points.contains(where: { $0.cents != 0 }) {
                    note.bend = bend
                }
            }
            note.vibrato = element.child("Vibrato") != nil
            note.letRing = element.child("LetRing") != nil
            note.palmMute = flag("PalmMuted")
            note.isDead = flag("Muted")
            note.isGhost = element.child("AntiAccent") != nil
            note.accent = (element.text("Accent").flatMap(Int.init) ?? 0) & (4 | 8) != 0
            note.tapped = flag("Tapped")
            if flag("Harmonic") || flag("HarmonicType") {
                switch element.property("HarmonicType")?.text("HType")?.lowercased() {
                case "artificial", "feedback": note.harmonic = .artificial
                case "pinch": note.harmonic = .pinch
                case "tap": note.harmonic = .tapped
                case "semi": note.harmonic = .semi
                default: note.harmonic = .natural
                }
            }
            return note
        }
    }

    // MARK: Writing

    static func write(_ score: TabScore) -> Data {
        var xml = XMLWriter()
        xml.line("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        xml.open("GPIF")
        xml.element("GPVersion", "7")
        xml.line("<GPRevision required=\"12021\" recommended=\"12023\">12025</GPRevision>")
        xml.open("Encoding")
        xml.element("EncodingDescription", "GP7")
        xml.close("Encoding")

        xml.open("Score")
        for (name, value) in [("Title", score.title), ("SubTitle", ""), ("Artist", score.artist), ("Album", score.album),
                              ("Words", ""), ("Music", ""), ("WordsAndMusic", ""), ("Copyright", ""), ("Tabber", ""),
                              ("Instructions", ""), ("Notices", "")] {
            xml.text(name, value)
        }
        xml.element("ScoreSystemsDefaultLayout", "4")
        xml.element("ScoreSystemsLayout", "4")
        xml.element("ScoreZoomPolicy", "Value")
        xml.element("ScoreZoom", "1")
        xml.element("MultiVoice", "0>")
        xml.close("Score")

        // Tempo: at the start and wherever a bar changes it
        xml.open("MasterTrack")
        xml.element("Tracks", score.tracks.indices.map(String.init).joined(separator: " "))
        xml.open("Automations")
        let changes = [(0, score.tempo)] + score.masterBars.enumerated().compactMap { index, bar in
            bar.tempo.flatMap { index == 0 ? nil : (index, $0) }
        }
        for (bar, tempo) in changes {
            xml.open("Automation")
            xml.element("Type", "Tempo")
            xml.element("Linear", "false")
            xml.element("Bar", "\(bar)")
            xml.element("Position", "0")
            xml.element("Visible", "true")
            xml.element("Value", "\(GPIF.number(tempo)) 2")
            xml.close("Automation")
        }
        xml.close("Automations")
        xml.close("MasterTrack")

        // Ids, and what the tracks' beats and notes become
        let content = Content(score: score)

        xml.open("Tracks")
        for (index, track) in score.tracks.enumerated() {
            writeTrack(track, index: index, chords: content.chordNames[index], to: &xml)
        }
        xml.close("Tracks")

        xml.open("MasterBars")
        var previousKey: Key?
        for (index, bar) in score.masterBars.enumerated() {
            xml.open("MasterBar")
            let key = bar.key ?? previousKey ?? Key(conventional: PitchClass(0), .major)
            previousKey = key
            xml.open("Key")
            xml.element("AccidentalCount", "\(GPIF.accidentals(of: key))")
            xml.element("Mode", key.quality == .minor ? "Minor" : "Major")
            xml.element("TransposeAs", GPIF.accidentals(of: key) < 0 ? "Flats" : "Sharps")
            xml.close("Key")
            xml.element("Time", bar.timeSignature.description)
            if bar.isRepeatStart || bar.repeatCount > 0 {
                xml.line("<Repeat start=\"\(bar.isRepeatStart)\" end=\"\(bar.repeatCount > 0)\" count=\"\(bar.repeatCount)\" />")
            }
            if !bar.alternateEndings.isEmpty {
                xml.element("AlternateEndings", bar.alternateEndings.map(String.init).joined(separator: " "))
            }
            if let marker = bar.marker, !marker.isEmpty {
                xml.open("Section")
                xml.text("Letter", "")
                xml.text("Text", marker)
                xml.close("Section")
            }
            xml.element("Bars", score.tracks.indices.map { String(content.barID(track: $0, bar: index)) }.joined(separator: " "))
            xml.close("MasterBar")
        }
        xml.close("MasterBars")

        xml.open("Bars")
        for (id, bar) in content.bars.enumerated() {
            xml.line("<Bar id=\"\(id)\">")
            xml.element("Clef", bar.clef)
            xml.element("Voices", (bar.voices + Array(repeating: -1, count: max(0, 4 - bar.voices.count))).prefix(4)
                .map(String.init).joined(separator: " "))
            xml.close("Bar")
        }
        xml.close("Bars")

        xml.open("Voices")
        for (id, beats) in content.voices.enumerated() {
            xml.line("<Voice id=\"\(id)\">")
            xml.element("Beats", beats.map(String.init).joined(separator: " "))
            xml.close("Voice")
        }
        xml.close("Voices")

        xml.open("Beats")
        for (id, beat) in content.beats.enumerated() {
            writeBeat(beat, id: id, to: &xml)
        }
        xml.close("Beats")

        xml.open("Notes")
        for (id, note) in content.notes.enumerated() {
            writeNote(note, id: id, to: &xml)
        }
        xml.close("Notes")

        xml.open("Rhythms")
        for (id, duration) in content.rhythms.enumerated() {
            writeRhythm(duration, id: id, to: &xml)
        }
        xml.close("Rhythms")
        xml.close("GPIF")
        return Data(xml.output.utf8)
    }

    /// The flat, numbered lists GPIF wants, built from the tracks.
    private struct Content {
        struct Bar { var clef: String; var voices: [Int] }
        struct Beat { var beat: TabBeat; var rhythm: Int; var notes: [Int]; var chord: Int? }
        struct Note { var note: TabNote; var midi: Int; var tieOrigin = false; var hopoDestination = false }

        var bars: [Bar] = []
        var voices: [[Int]] = []
        var beats: [Beat] = []
        var notes: [Note] = []
        var rhythms: [TabDuration] = []
        /// Each track's chord names, in id order.
        var chordNames: [[String]] = []
        private var barIDs: [[Int]] = []

        init(score: TabScore) {
            for track in score.tracks {
                var chords: [String] = []
                var ids: [Int] = []
                // The last note on each string (for ties and hammer-ons, which mark both ends)
                var last: [Int: Int] = [:]
                let clef = (track.tuning.strings.first ?? 40) < 36 ? "F4" : "G2"
                for bar in track.bars {
                    var voiceIDs: [Int] = []
                    for (voiceIndex, voice) in bar.voices.enumerated() where !voice.beats.isEmpty {
                        var beatIDs: [Int] = []
                        for beat in voice.beats {
                            var noteIDs: [Int] = []
                            for note in beat.notes where note.string < track.stringCount {
                                let id = notes.count
                                var written = Note(note: note, midi: track.pitch(string: note.string, fret: note.fret))
                                if voiceIndex == 0, let previous = last[note.string] {
                                    if note.isTied { notes[previous].tieOrigin = true }
                                    if notes[previous].note.legato { written.hopoDestination = true }
                                }
                                notes.append(written)
                                noteIDs.append(id)
                                if voiceIndex == 0 { last[note.string] = id }
                            }
                            var chord: Int?
                            if let name = beat.chord, !name.isEmpty {
                                if let existing = chords.firstIndex(of: name) {
                                    chord = existing
                                } else {
                                    chord = chords.count
                                    chords.append(name)
                                }
                            }
                            beatIDs.append(beats.count)
                            beats.append(Beat(beat: beat, rhythm: rhythm(for: beat.duration), notes: noteIDs, chord: chord))
                        }
                        voiceIDs.append(voices.count)
                        voices.append(beatIDs)
                    }
                    ids.append(bars.count)
                    bars.append(Bar(clef: clef, voices: voiceIDs))
                }
                barIDs.append(ids)
                chordNames.append(chords)
            }
        }

        func barID(track: Int, bar: Int) -> Int {
            barIDs[track].indices.contains(bar) ? barIDs[track][bar] : -1
        }

        private mutating func rhythm(for duration: TabDuration) -> Int {
            if let index = rhythms.firstIndex(of: duration) { return index }
            rhythms.append(duration)
            return rhythms.count - 1
        }
    }

    private static func writeTrack(_ track: TabTrack, index: Int, chords: [String], to xml: inout XMLWriter) {
        let isBass = (track.tuning.strings.first ?? 40) < 36
        let isAcoustic = (24...25).contains(track.midiProgram)
        xml.line("<Track id=\"\(index)\">")
        xml.text("Name", track.name)
        xml.text("ShortName", String(track.name.prefix(8)))
        xml.element("Color", ["235 152 125", "125 180 235", "150 210 120", "220 130 200", "235 200 110"][index % 5])
        xml.element("SystemsDefautLayout", "3")
        xml.element("SystemsLayout", "1")
        xml.element("PalmMute", "0")
        xml.element("AutoAccentuation", "0")
        xml.element("PlayingStyle", "Default")
        xml.empty("UseOneChannelPerString")
        xml.element("IconId", isBass ? "4" : isAcoustic ? "1" : "2")
        xml.open("InstrumentSet")
        xml.element("Name", isBass ? "Electric Bass" : isAcoustic ? "Steel Guitar" : "Electric Guitar")
        xml.element("Type", isBass ? "electricBass" : isAcoustic ? "steelGuitar" : "electricGuitar")
        xml.element("LineCount", "5")
        xml.open("Elements")
        xml.open("Element")
        xml.element("Name", "Pitched")
        xml.element("Type", "pitched")
        xml.empty("SoundbankName")
        xml.open("Articulations")
        xml.open("Articulation")
        xml.empty("Name")
        xml.element("StaffLine", "0")
        xml.element("Noteheads", "noteheadBlack noteheadHalf noteheadWhole")
        xml.element("TechniquePlacement", "outside")
        xml.empty("TechniqueSymbol")
        xml.empty("InputMidiNumbers")
        xml.empty("OutputRSESound")
        xml.element("OutputMidiNumber", "0")
        xml.close("Articulation")
        xml.close("Articulations")
        xml.close("Element")
        xml.close("Elements")
        xml.close("InstrumentSet")
        xml.open("Transpose")
        xml.element("Chromatic", "0")
        xml.element("Octave", "-1")
        xml.close("Transpose")
        xml.element("ForcedSound", "-1")
        xml.open("Sounds")
        xml.open("Sound")
        let sound = isBass ? "Clean Bass" : isAcoustic ? "Steel Guitar" : "Clean Guitar"
        xml.text("Name", sound)
        xml.text("Label", sound)
        xml.element("Path", isBass ? "Stringed/Basses/Clean Bass" : isAcoustic ? "Stringed/Acoustic Guitars/Steel Guitar"
                                                                               : "Stringed/Electric Guitars/Clean Guitar")
        xml.element("Role", "User")
        xml.open("MIDI")
        xml.element("LSB", "0")
        xml.element("MSB", "0")
        xml.element("Program", "\(min(max(track.midiProgram, 0), 127))")
        xml.close("MIDI")
        xml.close("Sound")
        xml.close("Sounds")
        xml.open("MidiConnection")
        xml.element("Port", "0")
        xml.element("PrimaryChannel", "\(index * 2 % 16 == 9 ? 10 : index * 2 % 16)")
        xml.element("SecondaryChannel", "\((index * 2 + 1) % 16 == 9 ? 11 : (index * 2 + 1) % 16)")
        xml.element("ForeOneChannelPerString", "false")
        xml.close("MidiConnection")
        xml.element("PlaybackState", "Default")
        xml.element("AudioEngineState", "MIDI")
        xml.open("Staves")
        xml.open("Staff")
        xml.open("Properties")
        xml.property("CapoFret") { $0.element("Fret", "\(track.capo)") }
        xml.property("FretCount") { $0.element("Number", "24") }
        xml.property("PartialCapoFret") { $0.element("Fret", "0") }
        xml.property("PartialCapoStringFlags") { $0.element("Bitset", String(repeating: "0", count: track.stringCount)) }
        xml.property("Tuning") {
            $0.element("Pitches", track.tuning.strings.map(String.init).joined(separator: " "))
            $0.element("Instrument", isBass ? "Bass" : "Guitar")
            $0.text("Label", "")
            $0.element("LabelVisible", "true")
        }
        for collection in ["ChordCollection", "ChordWorkingSet", "DiagramWorkingSet"] {
            xml.property(collection) { $0.empty("Items") }
        }
        xml.property("DiagramCollection") { xml in
            if chords.isEmpty {
                xml.empty("Items")
            } else {
                xml.open("Items")
                for (id, name) in chords.enumerated() {
                    xml.line("<Item id=\"\(id)\" name=\"\(XMLWriter.escape(name))\">")
                    xml.line("<Diagram stringCount=\"\(track.stringCount)\" fretCount=\"5\" baseFret=\"0\" barsStates=\"1 1 1 1 1\">")
                    xml.line("<Property name=\"ShowName\" type=\"bool\" value=\"true\" />")
                    xml.line("<Property name=\"ShowDiagram\" type=\"bool\" value=\"false\" />")
                    xml.line("<Property name=\"ShowFingering\" type=\"bool\" value=\"false\" />")
                    xml.close("Diagram")
                    xml.close("Item")
                }
                xml.close("Items")
            }
        }
        xml.text("Name", "Standard")
        xml.close("Properties")
        xml.close("Staff")
        xml.close("Staves")
        xml.empty("Automations")
        xml.close("Track")
    }

    private static func writeBeat(_ beat: Content.Beat, id: Int, to xml: inout XMLWriter) {
        xml.line("<Beat id=\"\(id)\">")
        xml.element("Dynamic", "MF")
        xml.line("<Rhythm ref=\"\(beat.rhythm)\" />")
        xml.open("Properties")
        if let stroke = beat.beat.stroke {
            xml.property("Brush") { $0.element("Direction", stroke == .down ? "Down" : "Up") }
        }
        xml.close("Properties")
        if let text = beat.beat.text, !text.isEmpty {
            xml.text("FreeText", text)
        }
        if let chord = beat.chord {
            xml.element("Chord", "\(chord)")
        }
        if beat.beat.tremoloPicking {
            xml.element("Tremolo", "1/8")
        }
        // Guitar Pro writes the notes last
        if !beat.notes.isEmpty {
            xml.element("Notes", beat.notes.map(String.init).joined(separator: " "))
        }
        xml.close("Beat")
    }

    private static func writeNote(_ written: Content.Note, id: Int, to xml: inout XMLWriter) {
        let note = written.note
        xml.line("<Note id=\"\(id)\">")
        xml.element("InstrumentArticulation", "0")
        xml.open("Properties")
        // Guitar Pro leaves out notes without their pitches. Guitars are written an octave above how they sound.
        xml.property("ConcertPitch") { GPIF.pitch(written.midi, to: &$0) }
        xml.property("TransposedPitch") { GPIF.pitch(written.midi + 12, to: &$0) }
        xml.property("String") { $0.element("String", "\(note.string)") }
        xml.property("Fret") { $0.element("Fret", "\(note.fret)") }
        xml.property("Midi") { $0.element("Number", "\(written.midi)") }
        func enable(_ name: String) { xml.property(name) { $0.empty("Enable") } }
        if note.palmMute { enable("PalmMuted") }
        if note.isDead { enable("Muted") }
        if note.legato { enable("HopoOrigin") }
        if written.hopoDestination { enable("HopoDestination") }
        if note.tapped { enable("Tapped") }
        if let slide = note.slide {
            let flags: [TabNote.Slide: Int] = [.shift: 1, .legato: 2, .outDownwards: 4, .outUpwards: 8, .inFromBelow: 16, .inFromAbove: 32]
            xml.property("Slide") { $0.element("Flags", "\(flags[slide] ?? 1)") }
        }
        if let harmonic = note.harmonic {
            let types: [TabNote.Harmonic: String] = [.natural: "Natural", .artificial: "Artificial", .pinch: "Pinch",
                                                     .tapped: "Tap", .semi: "Semi"]
            enable("Harmonic")
            xml.property("HarmonicType") { $0.element("HType", types[harmonic] ?? "Natural") }
            if harmonic == .natural {
                xml.property("HarmonicFret") { $0.element("HFret", GPIF.float(Double(note.fret))) }
            }
        }
        if let bend = note.bend, let first = bend.points.first, let last = bend.points.last {
            // Guitar Pro 7 has origin, up to two middle points sharing a value, and destination: a bend with more
            // points (Guitar Pro 3–5 allows any number) is simplified to the furthest one
            enable("Bended")
            // Positions to more places than Guitar Pro's own six, so sixtieths (from Guitar Pro 3–5) come back exactly
            func value(_ cents: Int) -> String { GPIF.float(Double(cents) / 2) }
            func offset(_ position: Double) -> String { String(position * 100) }
            xml.property("BendOriginValue") { $0.element("Float", value(first.cents)) }
            xml.property("BendOriginOffset") { $0.element("Float", offset(first.position)) }
            let middle = Array(bend.points.dropFirst().dropLast())
            if let peak = middle.max(by: { abs($0.cents - first.cents) < abs($1.cents - first.cents) }) {
                let level = middle.filter { $0.cents == peak.cents }
                xml.property("BendMiddleValue") { $0.element("Float", value(peak.cents)) }
                xml.property("BendMiddleOffset1") { $0.element("Float", offset(level.first!.position)) }
                xml.property("BendMiddleOffset2") { $0.element("Float", offset(level.last!.position)) }
            }
            xml.property("BendDestinationValue") { $0.element("Float", value(last.cents)) }
            xml.property("BendDestinationOffset") { $0.element("Float", offset(last.position)) }
        }
        xml.close("Properties")
        if written.tieOrigin || note.isTied {
            xml.line("<Tie origin=\"\(written.tieOrigin)\" destination=\"\(note.isTied)\" />")
        }
        if note.letRing { xml.empty("LetRing") }
        if note.vibrato { xml.element("Vibrato", "Slight") }
        if note.isGhost { xml.element("AntiAccent", "Normal") }
        if note.accent { xml.element("Accent", "8") }
        xml.close("Note")
    }

    private static func writeRhythm(_ duration: TabDuration, id: Int, to xml: inout XMLWriter) {
        let names: [TabDuration.Value: String] = [.whole: "Whole", .half: "Half", .quarter: "Quarter", .eighth: "Eighth",
                                                  .sixteenth: "16th", .thirtySecond: "32nd", .sixtyFourth: "64th"]
        xml.line("<Rhythm id=\"\(id)\">")
        xml.element("NoteValue", names[duration.value] ?? "Quarter")
        if duration.dots > 0 {
            xml.line("<AugmentationDot count=\"\(duration.dots)\" />")
        }
        if let tuplet = duration.tuplet {
            xml.line("<PrimaryTuplet num=\"\(tuplet.notes)\" den=\"\(tuplet.times)\" />")
        }
        xml.close("Rhythm")
    }

    // MARK: Helpers

    /// `<Pitch><Step>C</Step><Accidental>#</Accidental><Octave>4</Octave></Pitch>` for a MIDI note (60 is C4).
    fileprivate static func pitch(_ midi: Int, to xml: inout XMLWriter) {
        let steps = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
        let pitchClass = (midi % 12 + 12) % 12
        xml.open("Pitch")
        xml.element("Step", steps[pitchClass])
        if [1, 3, 6, 8, 10].contains(pitchClass) {
            xml.element("Accidental", "#")
        } else {
            xml.empty("Accidental")
        }
        xml.element("Octave", "\(midi / 12 - 1)")
        xml.close("Pitch")
    }

    static func numbers(_ text: String) -> [Int] {
        text.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
    }

    /// Guitar Pro tempos are in a beat unit: 1 eighth, 2 quarter, 3 dotted quarter, 4 half, 5 dotted half.
    static func quarters(perTempoUnit unit: Int) -> Double {
        [1: 0.5, 2: 1, 3: 1.5, 4: 2, 5: 3][unit] ?? 1
    }

    /// The key with this many sharps (positive) or flats (negative).
    static func key(accidentals: Int, minor: Bool) -> Key {
        let major = PitchClass(((accidentals * 7) % 12 + 12) % 12)
        let quality: KeyQuality = minor ? .minor : .major
        let tonic = minor ? major.transposed(by: 9) : major
        // Flat keys are spelled with flats (G♭ not F♯ for 6 flats)
        if accidentals < 0, let spelled = SpelledNote(["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"][tonic.value]) {
            return Key(spelled, quality)
        }
        return Key(conventional: tonic, quality)
    }

    /// Sharps (positive) or flats (negative) in the key signature.
    static func accidentals(of key: Key) -> Int {
        let major = key.quality == .minor ? key.tonic.pitchClass.transposed(by: 3) : key.tonic.pitchClass
        let sharps = (major.value * 7) % 12
        // As sharps or as flats: whichever spells the tonic the same way (A♭ minor is 7 flats, G♯ minor 5 sharps)
        let candidates = [sharps, sharps - 12].filter { (-7...7).contains($0) }
        return candidates.first { GPIF.key(accidentals: $0, minor: key.quality == .minor).tonic == key.tonic }
            ?? candidates.min { abs($0) < abs($1) } ?? 0
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    static func float(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

// MARK: - XML

private extension XMLElement {
    func child(_ path: String) -> XMLElement? {
        var element: XMLElement? = self
        for name in path.split(separator: "/") {
            element = element?.elements(forName: String(name)).first
        }
        return element
    }

    /// The trimmed text of a child (or of this element, for ""); nil if it's missing or empty.
    func text(_ path: String) -> String? {
        let element = path.isEmpty ? self : child(path)
        guard let value = element?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    func attribute(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }

    /// `<Properties><Property name="...">`
    func property(_ name: String) -> XMLElement? {
        child("Properties")?.elements(forName: "Property").first { $0.attribute("name") == name }
    }
}

/// Builds indented XML text.
private struct XMLWriter {
    var output = ""
    private var depth = 0

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    mutating func line(_ text: String) {
        output += String(repeating: "  ", count: depth) + text + "\n"
        if text.hasPrefix("<"), !text.hasPrefix("</"), !text.hasPrefix("<?"), !text.hasSuffix("/>"), !text.contains("</") {
            depth += 1
        }
    }

    mutating func open(_ name: String) {
        line("<\(name)>")
    }

    mutating func close(_ name: String) {
        depth = max(depth - 1, 0)
        output += String(repeating: "  ", count: depth) + "</\(name)>\n"
    }

    mutating func element(_ name: String, _ value: String) {
        line("<\(name)>\(XMLWriter.escape(value))</\(name)>")
    }

    mutating func empty(_ name: String) {
        line("<\(name) />")
    }

    /// Text in CDATA, as Guitar Pro writes names and titles.
    mutating func text(_ name: String, _ value: String) {
        line("<\(name)><![CDATA[\(value.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>"))]]></\(name)>")
    }

    mutating func property(_ name: String, _ body: (inout XMLWriter) -> Void) {
        line("<Property name=\"\(name)\">")
        body(&self)
        close("Property")
    }
}
