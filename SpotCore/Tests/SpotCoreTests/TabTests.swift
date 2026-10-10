import XCTest
@testable import SpotCore

final class TabModelTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(TabDuration(.quarter).ticks, 960)
        XCTAssertEqual(TabDuration(.whole).ticks, 3840)
        XCTAssertEqual(TabDuration(.quarter, dots: 1).ticks, 1440)
        XCTAssertEqual(TabDuration(.half, dots: 2).ticks, 3360)
        XCTAssertEqual(TabDuration(.eighth, tuplet: .triplet).ticks, 320)
        XCTAssertEqual(TabDuration(.sixteenth, tuplet: TabDuration.Tuplet(5, in: 4)).ticks, 192)

        XCTAssertEqual(TimeSignature(4, 4).ticks, 3840)
        XCTAssertEqual(TimeSignature(6, 8).ticks, 2880)
        XCTAssertEqual(TimeSignature(7, 8).ticks, 3360)
    }

    func testBarsStayInStepAcrossTracks() {
        var score = TabScore.empty(bars: 4)
        score.tracks.append(TabTrack(name: "Bass", tuning: .bass, midiProgram: 34, barCount: 4))
        score.masterBars[1].timeSignature = TimeSignature(3, 4)
        score.tracks[0].bars[1].voices[0].beats = [TabBeat(notes: [TabNote(string: 5, fret: 3)])]

        score.insertBar(after: 1)
        XCTAssertEqual(score.barCount, 5)
        XCTAssertEqual(score.masterBars[2].timeSignature, TimeSignature(3, 4), "a new bar carries on the time signature")
        XCTAssertTrue(score.tracks.allSatisfy { $0.bars.count == 5 })
        XCTAssertTrue(score.tracks[0].bars[2].isEmpty)
        XCTAssertFalse(score.tracks[0].bars[1].isEmpty)

        score.removeBar(at: 1)
        XCTAssertEqual(score.barCount, 4)
        XCTAssertTrue(score.tracks[0].bars.allSatisfy(\.isEmpty))
    }

    func testPitchIncludesTheCapo() {
        var track = TabTrack(name: "Guitar")
        XCTAssertEqual(track.pitch(string: 0, fret: 3), 43, "G2 on the low E")
        track.capo = 2
        XCTAssertEqual(track.pitch(string: 5, fret: 0), 66, "high E with a capo on 2 is F#4")
    }

    func testFileRoundTrip() throws {
        var score = TabScore.empty(bars: 2)
        score.title = "Test"
        score.artist = "Spot"
        score.tempo = 96
        score.masterBars[0] = MasterBar(timeSignature: TimeSignature(6, 8), key: Key(SpelledNote("G")!, .major),
                                        isRepeatStart: true, marker: "Intro", tempo: 100)
        score.masterBars[1].repeatCount = 2
        score.masterBars[1].alternateEndings = [1]
        score.tracks[0].capo = 3
        score.tracks[0].bars[0].voices[0].beats = [
            TabBeat(duration: TabDuration(.eighth, dots: 1),
                    notes: [TabNote(string: 3, fret: 7, legato: true, bend: .up(200), vibrato: true),
                            TabNote(string: 2, fret: 5, slide: .shift, palmMute: true, harmonic: .natural)],
                    chord: "Am7", stroke: .down),
            TabBeat(duration: TabDuration(.sixteenth, tuplet: .triplet)),
        ]
        let decoded = try TabScore.decode(from: score.encoded())
        XCTAssertEqual(decoded, score)

        let newer = #"{"version": 99}"#
        XCTAssertThrowsError(try TabScore.decode(from: Data(newer.utf8)))

        // Missing track bars are filled in, so every track lines up with the master bars
        let ragged = #"{"version": 1, "masterBars": [{"timeSignature": {"numerator": 4, "denominator": 4}, "isRepeatStart": false, "repeatCount": 0, "alternateEndings": []}, {"timeSignature": {"numerator": 4, "denominator": 4}, "isRepeatStart": false, "repeatCount": 0, "alternateEndings": []}], "tracks": [{"id": "6F9619FF-8B86-D011-B42D-00CF4FC964FF", "name": "G", "tuning": {"id": "guitar.standard", "name": "Standard", "strings": ["E2", "A2", "D3", "G3", "B3", "E4"]}, "capo": 0, "midiProgram": 25, "bars": []}]}"#
        XCTAssertEqual(try TabScore.decode(from: Data(ragged.utf8)).tracks[0].bars.count, 2)
    }
}

final class TabEditingTests: XCTestCase {
    let quarter = TabDuration(.quarter)

    func testEnteringNotesAndRests() {
        var score = TabScore.empty(bars: 2)
        // Typing on the empty slot adds a beat; typing on another string adds to the same beat
        let first = score.setNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 5, fret: 3, duration: quarter)
        XCTAssertEqual(first, 0)
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 2, fret: 0, duration: quarter)
        XCTAssertEqual(score.beats(track: 0, bar: 0).count, 1)
        XCTAssertEqual(score.beats(track: 0, bar: 0)[0].notes.map(\.string), [2, 5], "kept in string order")
        // Same string replaces the fret
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 5, fret: 5, duration: quarter)
        XCTAssertEqual(score.beats(track: 0, bar: 0)[0].notes.first { $0.string == 5 }?.fret, 5)

        score.setRest(track: 0, at: TabPosition(bar: 0, beat: 1), duration: TabDuration(.half))
        XCTAssertEqual(score.ticks(track: 0, bar: 0), 960 + 1920)
        XCTAssertEqual(score.fill(track: 0, bar: 0), -960, "a quarter short")
        XCTAssertFalse(score.isFull(track: 0, bar: 0))
        score.insertBeat(track: 0, at: TabPosition(bar: 0, beat: 1), duration: quarter)
        XCTAssertTrue(score.isFull(track: 0, bar: 0))
        XCTAssertEqual(score.fill(track: 0, bar: 1), 0, "an empty bar counts as a full-bar rest")

        score.removeNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 2)
        score.removeNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 5)
        XCTAssertTrue(score.beats(track: 0, bar: 0)[0].isRest)
        score.removeBeat(track: 0, at: TabPosition(bar: 0, beat: 0))
        XCTAssertEqual(score.beats(track: 0, bar: 0).count, 2)
    }

    func testTies() {
        var score = TabScore.empty(bars: 2)
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 3, fret: 7, duration: TabDuration(.whole))
        score.setRest(track: 0, at: TabPosition(bar: 1, beat: 0), duration: quarter)
        // The first beat of bar 2 ties back to the last of bar 1
        score.toggleTie(track: 0, at: TabPosition(bar: 1, beat: 0), string: 3)
        let tied = score.beats(track: 0, bar: 1)[0].notes.first
        XCTAssertEqual(tied?.fret, 7)
        XCTAssertEqual(tied?.isTied, true)
        score.toggleTie(track: 0, at: TabPosition(bar: 1, beat: 0), string: 3)
        XCTAssertEqual(score.beats(track: 0, bar: 1)[0].notes.first?.isTied, false)
        // Nothing to tie to on another string
        score.toggleTie(track: 0, at: TabPosition(bar: 1, beat: 0), string: 0)
        XCTAssertNil(score.beats(track: 0, bar: 1)[0].notes.first { $0.string == 0 })
    }

    func testCopyCutPaste() {
        var score = TabScore.empty(bars: 3)
        for (bar, frets) in [(0, [1, 2, 3, 4]), (1, [5, 6, 7, 8])] {
            for (beat, fret) in frets.enumerated() {
                score.setNote(track: 0, at: TabPosition(bar: bar, beat: beat), string: 0, fret: fret, duration: quarter)
            }
        }
        let copied = score.beats(track: 0, from: TabPosition(bar: 1, beat: 1), to: TabPosition(bar: 0, beat: 2))
        XCTAssertEqual(copied.map { $0.notes[0].fret }, [3, 4, 5, 6], "across the bar line, in order either way round")

        score.insertBeats(copied, track: 0, at: TabPosition(bar: 2, beat: 0))
        XCTAssertEqual(score.beats(track: 0, bar: 2).map { $0.notes[0].fret }, [3, 4, 5, 6])
        XCTAssertNotEqual(score.beats(track: 0, bar: 2)[0].id, copied[0].id, "pasted beats are new beats")

        score.removeBeats(track: 0, from: TabPosition(bar: 0, beat: 3), to: TabPosition(bar: 1, beat: 0))
        XCTAssertEqual(score.beats(track: 0, bar: 0).map { $0.notes[0].fret }, [1, 2, 3])
        XCTAssertEqual(score.beats(track: 0, bar: 1).map { $0.notes[0].fret }, [6, 7, 8])
    }

    func testTimeSignatureCarriesOn() {
        var score = TabScore.empty(bars: 6)
        score.masterBars[4].timeSignature = TimeSignature(6, 8)
        score.setTimeSignature(TimeSignature(3, 4), from: 1)
        XCTAssertEqual(score.masterBars.map(\.timeSignature.description), ["4/4", "3/4", "3/4", "3/4", "6/8", "4/4"])
    }
}

final class TabPerformanceTests: XCTestCase {
    private func noteOns(_ performance: TabPerformance) -> [(time: Double, channel: Int, note: Int, velocity: Int)] {
        performance.events.compactMap { event in
            if case .noteOn(let channel, let note, let velocity) = event.message { return (event.time, channel, note, velocity) }
            return nil
        }
    }

    private func noteOffs(_ performance: TabPerformance) -> [(time: Double, note: Int)] {
        performance.events.compactMap { event in
            if case .noteOff(_, let note) = event.message { return (event.time, note) }
            return nil
        }
    }

    func testRepeatsAndEndings() {
        var score = TabScore.empty(bars: 5)
        score.masterBars[1].isRepeatStart = true
        score.masterBars[2].alternateEndings = [1]
        score.masterBars[2].repeatCount = 2
        score.masterBars[3].alternateEndings = [2]
        XCTAssertEqual(TabPerformance.playingOrder(score), [0, 1, 2, 1, 3, 4])

        // Three times through, no endings
        var thrice = TabScore.empty(bars: 3)
        thrice.masterBars[0].isRepeatStart = true
        thrice.masterBars[1].repeatCount = 3
        XCTAssertEqual(TabPerformance.playingOrder(thrice), [0, 1, 0, 1, 0, 1, 2])

        // No repeat start: back to the beginning
        var fromTop = TabScore.empty(bars: 3)
        fromTop.masterBars[1].repeatCount = 2
        XCTAssertEqual(TabPerformance.playingOrder(fromTop), [0, 1, 0, 1, 2])
    }

    func testTimingTempoChangesAndClicks() {
        var score = TabScore.empty(bars: 2)
        score.tempo = 120
        score.masterBars[1].tempo = 60
        score.masterBars[1].timeSignature = TimeSignature(3, 4)
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 0, fret: 0, duration: TabDuration(.whole))
        score.setNote(track: 0, at: TabPosition(bar: 1, beat: 0), string: 1, fret: 0, duration: TabDuration(.quarter))
        score.setNote(track: 0, at: TabPosition(bar: 1, beat: 1), string: 1, fret: 2, duration: TabDuration(.quarter))
        let performance = TabPerformance.make(score)
        // 4/4 at 120 is 2 s; then 3/4 at 60 is 3 s
        XCTAssertEqual(performance.length, 5, accuracy: 1e-9)
        XCTAssertEqual(noteOns(performance).map(\.time), [0, 2, 3])
        XCTAssertEqual(noteOns(performance).map(\.note), [40, 45, 47])
        XCTAssertEqual(performance.clicks.map(\.time), [0, 0.5, 1, 1.5, 2, 3, 4])
        XCTAssertEqual(performance.clicks.map(\.isAccent), [true, false, false, false, true, false, false])

        XCTAssertEqual(performance.position(of: 0, at: 3.4)?.beat, 1)
        XCTAssertEqual(performance.position(of: 0, at: 3.4)?.bar, 1)
        XCTAssertTrue(performance.barAndBeat(at: 4.1)! == (2, 3))
        XCTAssertEqual(performance.time(of: TabPosition(bar: 1, beat: 1), track: 0), 3, accuracy: 1e-9)
    }

    func testTechniques() {
        var score = TabScore.empty(bars: 1)
        score.tempo = 60   // a quarter is a second
        let quarter = TabDuration(.quarter)
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 2, fret: 5, duration: quarter)
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 1), string: 2, fret: 5, duration: quarter)
        score.toggleTie(track: 0, at: TabPosition(bar: 0, beat: 1), string: 2)
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 2), string: 3, fret: 12, duration: quarter)
        score.updateNote(track: 0, at: TabPosition(bar: 0, beat: 2), string: 3) { $0.harmonic = .natural; $0.accent = true }
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 3), string: 0, fret: 0, duration: quarter)
        score.updateNote(track: 0, at: TabPosition(bar: 0, beat: 3), string: 0) { $0.isDead = true }
        score.tracks[0].capo = 2

        let performance = TabPerformance.make(score)
        let ons = noteOns(performance)
        // The tie doesn't strike again: three notes, not four
        XCTAssertEqual(ons.map(\.note), [50 + 2 + 5, 55 + 2 + 12, 40 + 2])
        XCTAssertEqual(ons[1].velocity, 120, "accent")
        // The tied note lasts both beats; the dead note is very short
        let offs = noteOffs(performance)
        XCTAssertEqual(offs.first { $0.note == 57 }?.time ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual((offs.first { $0.note == 42 }?.time ?? 0) - 3, 0.06, accuracy: 1e-9)
        // Each string its own channel
        XCTAssertEqual(Set(ons.map(\.channel)).count, 3)
        XCTAssertFalse(performance.channels.contains(9), "never the drum channel")
    }

    func testBendsSlidesAndLetRing() {
        var score = TabScore.empty(bars: 1)
        score.tempo = 60
        let quarter = TabDuration(.quarter)
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 3, fret: 7, duration: quarter)
        score.updateNote(track: 0, at: TabPosition(bar: 0, beat: 0), string: 3) { $0.bend = .up(200); $0.letRing = true }
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 1), string: 3, fret: 5, duration: quarter)
        score.updateNote(track: 0, at: TabPosition(bar: 0, beat: 1), string: 3) { $0.slide = .shift }
        score.setNote(track: 0, at: TabPosition(bar: 0, beat: 2), string: 3, fret: 9, duration: TabDuration(.half))
        let performance = TabPerformance.make(score)
        let bends = performance.events.compactMap { event -> (Double, Int)? in
            if case .pitchBend(_, let value) = event.message, event.time > 0 { return (event.time, value) }
            return nil
        }
        // The full bend reaches two semitones up
        XCTAssertEqual(bends.filter { $0.0 < 1 }.map(\.1).max(), TabPerformance.bendValue(cents: 200))
        // Let ring holds the bent note until the next note on the string
        XCTAssertEqual(noteOffs(performance).first { $0.note == 62 }?.time ?? 0, 1, accuracy: 1e-9)
        // The slide bends the 5 up towards the 9 just before it
        XCTAssertEqual(bends.filter { $0.0 > 1.5 && $0.0 < 2 }.map(\.1).max(), TabPerformance.bendValue(cents: 400))
    }
}

final class TabLinkTests: XCTestCase {
    /// Two bars of 4/4 repeated, chords Am (twice in a row), C, then G in the bar after.
    private func score() -> TabScore {
        var score = TabScore.empty(bars: 3)
        score.tempo = 90
        score.masterBars[0].isRepeatStart = true
        score.masterBars[1].repeatCount = 2
        score.masterBars[1].tempo = 200
        var beats = (0..<4).map { _ in TabBeat(duration: TabDuration(.quarter), notes: [TabNote(string: 0, fret: 0)]) }
        beats[0].chord = "Am"
        beats[2].chord = "Am"
        score.tracks[0].bars[0].voices[0].beats = beats
        var second = beats
        second[0].chord = "C"
        second[2].chord = nil
        score.tracks[0].bars[1].voices[0].beats = second
        var third = beats
        third[0].chord = "G"
        third[2].chord = nil
        score.tracks[0].bars[2].voices[0].beats = third
        return score
    }

    func testQuarterNoteTimingIgnoresTempo() {
        let performance = TabPerformance.make(score(), inQuarterNotes: true)
        XCTAssertEqual(performance.length, 20, accuracy: 1e-9) // 5 bars of 4, with the repeat
        XCTAssertEqual(performance.moments[0].map(\.time).prefix(5), [0, 1, 2, 3, 4])
        XCTAssertNotEqual(TabPerformance.make(score()).length, 20)
    }

    func testChordChangesFollowRepeats() {
        let changes = score().chordChanges(track: 0)
        XCTAssertEqual(changes.map(\.name), ["Am", "C", "Am", "C", "G"])
        XCTAssertEqual(changes.map(\.range), [BeatRange(0, 4), BeatRange(4, 8), BeatRange(8, 12), BeatRange(12, 16), BeatRange(16, 20)])
        XCTAssertEqual(score().chordChanges(track: 3).count, 0)
    }

    func testSequenceKeepsItsLink() throws {
        var sequence = ChordSequence()
        sequence.tab = TabLink(bookmark: nil, lastKnownPath: "/tmp/Song.spottab", fileName: "Song.spottab", track: 1, startBeat: 4, isMuted: true)
        let read = try JSONDecoder().decode(ChordSequence.self, from: sequence.encoded())
        XCTAssertEqual(read.tab, sequence.tab)
        XCTAssertEqual(read.tab?.name, "Song")
        // Files from before links still open
        var old = try JSONSerialization.jsonObject(with: sequence.encoded()) as! [String: Any]
        old["tab"] = nil
        XCTAssertNil(try JSONDecoder().decode(ChordSequence.self, from: JSONSerialization.data(withJSONObject: old)).tab)
    }
}
