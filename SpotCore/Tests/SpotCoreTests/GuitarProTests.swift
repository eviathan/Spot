import XCTest
@testable import SpotCore

final class GuitarProTests: XCTestCase {
    func testZipRoundTrip() throws {
        let files: [(path: String, data: Data)] = [
            ("VERSION", Data("7.0".utf8)),
            ("Content/score.gpif", Data(String(repeating: "<Beat>quite repetitive</Beat>", count: 200).utf8)),
            ("empty", Data()),
        ]
        let zip = Zip.archive(files)
        let read = try Zip.entries(of: zip)
        XCTAssertEqual(read.count, 3)
        for file in files {
            XCTAssertEqual(read[file.path], file.data, file.path)
        }
        XCTAssertLessThan(zip.count, 2000, "the repetitive file should be deflated")
        XCTAssertEqual(Zip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testKeySignatures() {
        for count in -7...7 {
            for minor in [false, true] {
                // The same key back (6 sharps or flats, and 7, can come back spelled the other way)
                let key = GPIF.key(accidentals: count, minor: minor)
                let again = GPIF.key(accidentals: GPIF.accidentals(of: key), minor: minor)
                XCTAssertEqual(again.tonic.pitchClass, key.tonic.pitchClass, "\(count) \(minor) → \(key)")
                XCTAssertEqual(again.quality, key.quality)
            }
        }
        XCTAssertEqual(GPIF.key(accidentals: -1, minor: false).description, Key(SpelledNote("F")!, .major).description)
        XCTAssertEqual(GPIF.key(accidentals: 3, minor: true).description, Key(SpelledNote("F#")!, .minor).description)
    }

    /// Everything the model holds survives a trip through Guitar Pro 7.
    func testRoundTrip() throws {
        let score = Self.everything()
        let data = GuitarPro.gp7(score)
        let read = try GuitarPro.read(data)
        XCTAssertEqual(read.skippedTracks, [])
        XCTAssertEqual(Self.withoutIDs(read.score), Self.withoutIDs(score))
        Self.reportDifferences(read.score, score)
    }

    static func reportDifferences(_ a: TabScore, _ b: TabScore) {
        let (a, b) = (withoutIDs(a), withoutIDs(b))
        for (i, (x, y)) in zip(a.masterBars, b.masterBars).enumerated() where x != y {
            print("DIFF master bar \(i): \(x) vs \(y)")
        }
        for (t, (x, y)) in zip(a.tracks, b.tracks).enumerated() {
            if x.tuning != y.tuning || x.capo != y.capo || x.midiProgram != y.midiProgram || x.name != y.name {
                print("DIFF track \(t) settings")
            }
            for (i, (p, q)) in zip(x.bars, y.bars).enumerated() where p != q {
                if p.voices.count != q.voices.count { print("DIFF track \(t) bar \(i) voices \(p.voices.count) vs \(q.voices.count)") }
                for (v, (m, n)) in zip(p.voices, q.voices).enumerated() {
                    for (k, (c, d)) in zip(m.beats, n.beats).enumerated() where c != d {
                        print("DIFF track \(t) bar \(i) voice \(v) beat \(k):\n  \(c)\n  \(d)")
                    }
                }
            }
        }
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try GuitarPro.read(Data("hello".utf8)))
        XCTAssertThrowsError(try GuitarPro.read(Data([0x18] + Array("FICHIER GUITAR PRO v5.00".utf8) + [0, 0, 0, 0, 0, 0])))
    }

    /// Real files, if there are some to try (set SPOT_GP_SAMPLES to a folder of .gp files): they read, and what's
    /// read survives being written and read again.
    func testSampleFiles() throws {
        guard let folder = ProcessInfo.processInfo.environment["SPOT_GP_SAMPLES"] else { throw XCTSkip("No samples") }
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "gp" }
        for url in urls {
            let read = try GuitarPro.read(Data(contentsOf: url))
            let score = read.score
            let notes = score.tracks.flatMap(\.bars).flatMap(\.voices).flatMap(\.beats).flatMap(\.notes)
            print("SAMPLE \(url.lastPathComponent): \(score.title) / \(score.artist), \(score.barCount) bars, tempo \(score.tempo), "
                  + "tracks \(score.tracks.map { "\($0.name) (\($0.stringCount) strings, capo \($0.capo), program \($0.midiProgram))" }), "
                  + "skipped \(read.skippedTracks), \(notes.count) notes, "
                  + "tempo changes \(score.masterBars.compactMap(\.tempo).count), markers \(score.masterBars.compactMap(\.marker)), "
                  + "bends \(notes.filter { $0.bend != nil }.count), slides \(notes.filter { $0.slide != nil }.count), "
                  + "ties \(notes.filter(\.isTied).count), harmonics \(notes.filter { $0.harmonic != nil }.count), "
                  + "chords \(Set(score.tracks.flatMap(\.bars).flatMap(\.voices).flatMap(\.beats).compactMap(\.chord)).sorted())")
            for track in score.tracks.indices {
                let unfilled = score.masterBars.indices.filter { score.fill(track: track, bar: $0) != 0 }
                print("SAMPLE   \(score.tracks[track].name): bars not adding up \(unfilled.prefix(10))")
            }
            let again = try GuitarPro.read(GuitarPro.gp7(score)).score
            XCTAssertEqual(Self.withoutIDs(again), Self.withoutIDs(score), url.lastPathComponent)
            if let out = ProcessInfo.processInfo.environment["SPOT_GP_OUT"] {
                try GuitarPro.gp7(score).write(to: URL(fileURLWithPath: out).appendingPathComponent("rt-" + url.lastPathComponent))
            }
        }
        if let out = ProcessInfo.processInfo.environment["SPOT_GP_OUT"] {
            try GuitarPro.gp7(Self.everything()).write(to: URL(fileURLWithPath: out).appendingPathComponent("everything.gp"))
        }
    }

    /// Guitar Pro 3–5 files, if there are some to try (SPOT_GP_OLD_SAMPLES, searched recursively): each is read to
    /// its very end (the binary format has no lengths, so ending exactly there means every field was read right).
    func testOldSampleFiles() throws {
        guard let folder = ProcessInfo.processInfo.environment["SPOT_GP_OLD_SAMPLES"] else { throw XCTSkip("No samples") }
        let files = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { ["gp3", "gp4", "gp5", "gpx"].contains($0.pathExtension) }
            .sorted { $0.path < $1.path }
        XCTAssertFalse(files.isEmpty)
        for url in files {
            let data = try Data(contentsOf: url)
            do {
                // (Guitar Pro 6 files are XML inside, so there's nothing to count)
                let (read, consumed) = url.pathExtension == "gpx" ? (try GuitarPro.read(data), data.count)
                                                                  : try GuitarProBinary.readCounting(data)
                let score = read.score
                let beats = score.tracks.flatMap(\.bars).flatMap(\.voices).flatMap(\.beats)
                let notes = beats.flatMap(\.notes)
                let unfilled = score.tracks.indices.flatMap { t in score.masterBars.indices.filter { score.fill(track: t, bar: $0) != 0 } }
                func count(_ test: (TabNote) -> Bool) -> Int { notes.filter(test).count }
                print("OLD \(url.lastPathComponent): \(data[consumed...].allSatisfy { $0 == 0 } ? "all read" : "READ \(consumed) OF \(data.count)"), "
                      + "\(score.barCount) bars, \(score.tracks.count) tracks \(score.tracks.map { "\($0.name)/\($0.stringCount)/capo \($0.capo)/prog \($0.midiProgram)" }), "
                      + "skipped \(read.skippedTracks), tempo \(score.tempo), \(notes.count) notes, unfilled bars \(unfilled.count), "
                      + "bends \(count { $0.bend != nil }) slides \(count { $0.slide != nil }) legato \(count(\.legato)) ties \(count(\.isTied)) "
                      + "harm \(count { $0.harmonic != nil }) dead \(count(\.isDead)) ghost \(count(\.isGhost)) acc \(count(\.accent)) "
                      + "vib \(count(\.vibrato)) pm \(count(\.palmMute)) ring \(count(\.letRing)) tap \(count(\.tapped)) "
                      + "strokes \(beats.filter { $0.stroke != nil }.count) trem \(beats.filter(\.tremoloPicking).count) "
                      + "chords \(Set(beats.compactMap(\.chord)).sorted()) text \(beats.compactMap(\.text).prefix(3)) "
                      + "markers \(score.masterBars.compactMap(\.marker).prefix(4)) repeats \(score.masterBars.map(\.repeatCount).filter { $0 > 0 }) "
                      + "endings \(score.masterBars.map(\.alternateEndings).filter { !$0.isEmpty }) times \(Set(score.masterBars.map(\.timeSignature.description)).sorted()) "
                      + "title \(score.title)")
                // What was read survives being written as Guitar Pro 7 and read back (bends by their height: Guitar
                // Pro 7 can't hold a bend with more than four points)
                let again = try GuitarPro.read(GuitarPro.gp7(score)).score
                if Self.withBendPeaks(again) != Self.withBendPeaks(score) {
                    XCTFail("\(url.lastPathComponent) round trip")
                    Self.reportDifferences(again, score)
                }
                // (Some files are padded with zeros at the end)
                XCTAssertTrue(data[consumed...].allSatisfy { $0 == 0 }, "\(url.lastPathComponent): read \(consumed) of \(data.count)")
            } catch {
                XCTFail("\(url.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: -

    /// Without ids, and each bend reduced to its height.
    static func withBendPeaks(_ score: TabScore) -> TabScore {
        var score = withoutIDs(score)
        for t in score.tracks.indices {
            for b in score.tracks[t].bars.indices {
                for v in score.tracks[t].bars[b].voices.indices {
                    for i in score.tracks[t].bars[b].voices[v].beats.indices {
                        for n in score.tracks[t].bars[b].voices[v].beats[i].notes.indices {
                            if let peak = score.tracks[t].bars[b].voices[v].beats[i].notes[n].bend?.peak {
                                score.tracks[t].bars[b].voices[v].beats[i].notes[n].bend = .up(peak)
                            }
                        }
                    }
                }
            }
        }
        return score
    }

    static func withoutIDs(_ score: TabScore) -> TabScore {
        var score = score
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        for t in score.tracks.indices {
            score.tracks[t].id = id
            for b in score.tracks[t].bars.indices {
                for v in score.tracks[t].bars[b].voices.indices {
                    for i in score.tracks[t].bars[b].voices[v].beats.indices {
                        score.tracks[t].bars[b].voices[v].beats[i].id = id
                    }
                }
            }
        }
        return score
    }

    static func everything() -> TabScore {
        var score = TabScore(title: "Everything & <More>", artist: "Spot", album: "Tests", tempo: 96)
        score.masterBars = [
            MasterBar(key: Key(conventional: PitchClass(7), .major), isRepeatStart: true, marker: "Intro"),
            MasterBar(repeatCount: 2, alternateEndings: [1]),
            MasterBar(alternateEndings: [2], tempo: 140),
            MasterBar(timeSignature: TimeSignature(6, 8), key: Key(SpelledNote("Eb")!, .minor), marker: "Verse"),
            MasterBar(timeSignature: TimeSignature(6, 8)),
        ]
        var guitar = TabTrack(name: "Lead", tuning: .dropD, capo: 2, midiProgram: 30, barCount: 5)
        var bass = TabTrack(name: "Bass", tuning: .bass, midiProgram: 34, barCount: 5)

        func beat(_ value: TabDuration.Value, _ notes: [TabNote], dots: Int = 0, tuplet: TabDuration.Tuplet? = nil) -> TabBeat {
            TabBeat(duration: TabDuration(value, dots: dots, tuplet: tuplet), notes: notes.sorted { $0.string < $1.string })
        }
        // Bar 1: legato, slides, ties
        var b0 = [
            beat(.eighth, [TabNote(string: 3, fret: 5, legato: true)]),
            beat(.eighth, [TabNote(string: 3, fret: 7)]),
            beat(.quarter, [TabNote(string: 2, fret: 5, slide: .shift)]),
            beat(.quarter, [TabNote(string: 2, fret: 9), TabNote(string: 0, fret: 0, letRing: true)]),
            beat(.quarter, [TabNote(string: 2, fret: 9, isTied: true), TabNote(string: 1, fret: 3, slide: .inFromBelow)]),
        ]
        b0[0].chord = "Am7"
        b0[3].chord = "D/F#"
        b0[2].text = "slowly"
        guitar.bars[0].voices[0].beats = b0
        // Bar 2: bends, vibrato, techniques
        guitar.bars[1].voices[0].beats = [
            beat(.quarter, [TabNote(string: 3, fret: 7, bend: .up(200), vibrato: true)]),
            beat(.quarter, [TabNote(string: 3, fret: 7, bend: .upAndRelease(100))]),
            beat(.quarter, [TabNote(string: 3, fret: 7, bend: .prebendRelease(300))]),
            beat(.eighth, [TabNote(string: 0, fret: 0, palmMute: true), TabNote(string: 1, fret: 0, isDead: true)]),
            beat(.eighth, [TabNote(string: 4, fret: 12, harmonic: .natural), TabNote(string: 5, fret: 5, isGhost: true, accent: true)]),
        ]
        // Bar 3: tuplets, dots, a strum, a tap, tremolo picking, a rest
        var b2 = [
            beat(.eighth, [TabNote(string: 5, fret: 12, tapped: true)], tuplet: .triplet),
            beat(.eighth, [TabNote(string: 5, fret: 8, harmonic: .pinch)], tuplet: .triplet),
            beat(.eighth, [], tuplet: .triplet),
            beat(.quarter, [TabNote(string: 0, fret: 3), TabNote(string: 1, fret: 2), TabNote(string: 2, fret: 0)], dots: 1),
            beat(.eighth, [TabNote(string: 4, fret: 3, slide: .outDownwards)]),
            beat(.quarter, [TabNote(string: 4, fret: 3, harmonic: .artificial)]),
        ]
        b2[3].stroke = .down
        b2[4].stroke = .up
        b2[5].tremoloPicking = true
        guitar.bars[2].voices[0].beats = b2
        // Bar 4 (6/8): sixteenths, a second voice; bar 5 empty
        guitar.bars[3].voices = [
            TabVoice(beats: [beat(.sixteenth, [TabNote(string: 1, fret: 1)]), beat(.sixteenth, [TabNote(string: 1, fret: 3)]),
                             beat(.half, [TabNote(string: 1, fret: 5, slide: .legato)], dots: 1)]),
            TabVoice(beats: [beat(.half, [TabNote(string: 0, fret: 0)], dots: 1)]),
        ]
        bass.bars[0].voices[0].beats = [beat(.whole, [TabNote(string: 0, fret: 5)])]
        bass.bars[3].voices[0].beats = [beat(.quarter, [TabNote(string: 1, fret: 0, harmonic: .semi)], dots: 1),
                                        beat(.quarter, [TabNote(string: 1, fret: 2, harmonic: .tapped)], dots: 1)]
        score.tracks = [guitar, bass]
        return score
    }
}
