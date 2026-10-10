//
//  TabPerformance.swift
//  SpotCore
//

import Foundation

/// A tab played out in time: repeats and 1st/2nd endings followed, tempo changes applied, and every note turned
/// into MIDI, with the techniques done as well as MIDI can (bends, slides and vibrato as pitch bend, palm mute
/// and dead notes short, ghost notes soft, accents loud, ties held, let ring sustained, harmonics at their pitch).
/// Times are in seconds from the start.
public struct TabPerformance: Sendable {
    public enum Message: Hashable, Sendable {
        case noteOn(channel: Int, note: Int, velocity: Int)
        case noteOff(channel: Int, note: Int)
        /// 14-bit, 8192 is no bend.
        case pitchBend(channel: Int, value: Int)
        case program(channel: Int, program: Int)
        case controller(channel: Int, number: Int, value: Int)
    }

    public struct Event: Hashable, Sendable {
        public var time: Double
        public var message: Message
    }

    public struct Click: Hashable, Sendable {
        public var time: Double
        public var isAccent: Bool
    }

    /// Where a beat of a track is played (the same beat can come up more than once, in repeats).
    public struct Moment: Hashable, Sendable {
        public var time: Double
        public var bar: Int
        public var beat: Int
    }

    /// In time order; at the same moment, notes end before new ones start.
    public var events: [Event]
    public var clicks: [Click]
    /// For each track, when each of its beats is played.
    public var moments: [[Moment]]
    /// Each bar as played, with when it starts (for "bar.beat").
    public var bars: [(time: Double, bar: Int, beatSeconds: Double)]
    public var length: Double
    /// The MIDI channels in use.
    public var channels: [Int]

    /// Pitch bend covers ±12 semitones (set at the start on every channel), so slides of up to an octave work.
    public static let bendRange = 12

    // MARK: - Making it

    public static func make(_ score: TabScore) -> TabPerformance {
        let barOrder = playingOrder(score)
        let channelMap = channels(for: score)
        var events: [Event] = []
        var clicks: [Click] = []
        var moments: [[Moment]] = Array(repeating: [], count: score.tracks.count)
        var bars: [(Double, Int, Double)] = []

        // Each channel: its sound, and a bend range of an octave
        for (track, perString) in channelMap.enumerated() {
            for channel in Set(perString) {
                events.append(Event(time: 0, message: .program(channel: channel, program: score.tracks[track].midiProgram)))
                for (number, value) in [(101, 0), (100, 0), (6, bendRange), (38, 0), (101, 127), (100, 127)] {
                    events.append(Event(time: 0, message: .controller(channel: channel, number: number, value: value)))
                }
                events.append(Event(time: 0, message: .pitchBend(channel: channel, value: 8192)))
            }
        }

        // The note sounding on each (track, string), to tie onto, slide from and stop for let ring
        struct Sounding { var index: Int; var note: Int; var channel: Int; var legatoNext: Bool; var slideNext: TabNote.Slide? }
        var sounding: [[Int: Sounding]] = Array(repeating: [:], count: score.tracks.count)
        // Note-off events, added once each note's end is known
        var noteEnds: [Int: Double] = [:]       // index of the noteOn event → end time
        var tempo = score.tempo
        var time = 0.0

        for bar in barOrder {
            let master = score.masterBars[bar]
            if let change = master.tempo { tempo = change }
            let secondsPerTick = 60 / tempo / Double(TabDuration.ticksPerQuarter)
            let barTicks = master.timeSignature.ticks
            let beatSeconds = Double(barTicks / max(master.timeSignature.numerator, 1)) * secondsPerTick
            bars.append((time, bar, beatSeconds))

            for click in 0..<master.timeSignature.numerator {
                clicks.append(Click(time: time + Double(click) * beatSeconds, isAccent: click == 0))
            }

            for (trackIndex, track) in score.tracks.enumerated() where track.bars.indices.contains(bar) {
                var beatTime = time
                for (beatIndex, beat) in track.bars[bar].voices[0].beats.enumerated() {
                    let duration = Double(beat.duration.ticks) * secondsPerTick
                    moments[trackIndex].append(Moment(time: beatTime, bar: bar, beat: beatIndex))
                    for note in beat.notes where track.tuning.strings.indices.contains(note.string) {
                        let channel = channelMap[trackIndex][note.string]
                        let pitch = sounds(note, on: track)
                        let previous = sounding[trackIndex][note.string]

                        // A tie holds the note on
                        if note.isTied, let previous, previous.note == pitch {
                            noteEnds[previous.index] = beatTime + duration
                            continue
                        }
                        // The previous note on this string stops here (let ring and slides included)
                        if let previous {
                            if let end = noteEnds[previous.index], end > beatTime {
                                noteEnds[previous.index] = beatTime
                            }
                            // A slide into this note: bend the previous one up or down to it over its last part
                            if previous.slideNext == .shift || previous.slideNext == .legato,
                               let start = noteEnds[previous.index].map({ _ in events[previous.index].time }) {
                                let slideStart = max(start, beatTime - min(0.12, (beatTime - start) * 0.5))
                                let semitones = pitch - previous.note
                                for step in 1...6 {
                                    let fraction = Double(step) / 6
                                    events.append(Event(time: slideStart + (beatTime - slideStart) * fraction - 0.001,
                                                        message: .pitchBend(channel: previous.channel,
                                                                            value: bendValue(cents: Int(Double(semitones * 100) * fraction)))))
                                }
                            }
                        }

                        var velocity = 95
                        if note.accent { velocity = 120 }
                        if note.isGhost { velocity = 50 }
                        if note.isDead { velocity = 70 }
                        if note.palmMute { velocity -= 10 }
                        if let previous, previous.legatoNext || previous.slideNext == .legato { velocity -= 25 }

                        var length = duration
                        if note.palmMute { length = min(duration * 0.5, 0.25) }
                        if note.isDead { length = min(duration, 0.06) }
                        if note.letRing { length = max(duration, 4) }

                        // Each note starts unbent
                        events.append(Event(time: beatTime, message: .pitchBend(channel: channel, value: 8192)))
                        events.append(Event(time: beatTime, message: .noteOn(channel: channel, note: pitch, velocity: max(1, velocity))))
                        let index = events.count - 1
                        noteEnds[index] = beatTime + length

                        if let bend = note.bend {
                            // Along the bend's curve, every 20 ms
                            let steps = max(2, Int(duration / 0.02))
                            for step in 0...steps {
                                let position = Double(step) / Double(steps)
                                events.append(Event(time: beatTime + duration * position,
                                                    message: .pitchBend(channel: channel, value: bendValue(cents: cents(bend, at: position)))))
                            }
                        } else if note.vibrato {
                            // A gentle wobble, ±25 cents at 5 Hz
                            let steps = Int(duration / 0.025)
                            for step in 0...max(steps, 0) {
                                let t = Double(step) * 0.025
                                events.append(Event(time: beatTime + t,
                                                    message: .pitchBend(channel: channel, value: bendValue(cents: Int(25 * sin(2 * .pi * 5 * t))))))
                            }
                        }
                        sounding[trackIndex][note.string] = Sounding(index: index, note: pitch, channel: channel,
                                                                     legatoNext: note.legato, slideNext: note.slide)
                    }
                    beatTime += duration
                }
            }
            time += Double(barTicks) * secondsPerTick
        }

        // Note-offs, now every note's end is known
        for (index, end) in noteEnds {
            if case .noteOn(let channel, let note, _) = events[index].message {
                events.append(Event(time: min(end, time + 4), message: .noteOff(channel: channel, note: note)))
            }
        }
        events.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return TabPerformance.order(of: lhs.message) < TabPerformance.order(of: rhs.message)
        }
        let used = Array(Set(channelMap.flatMap { $0 })).sorted()
        return TabPerformance(events: events, clicks: clicks, moments: moments, bars: bars, length: time, channels: used)
    }

    /// At the same moment: set things up, end notes, bend, then start notes.
    private static func order(of message: Message) -> Int {
        switch message {
        case .program, .controller: return 0
        case .noteOff: return 1
        case .pitchBend: return 2
        case .noteOn: return 3
        }
    }

    /// The bars in the order they're played: repeats played the right number of times, and bars with 1st/2nd
    /// endings only on their passes.
    public static func playingOrder(_ score: TabScore) -> [Int] {
        var order: [Int] = []
        var index = 0
        var repeatStart = 0
        var pass = 1
        var cameBack = false
        var guardCount = 0
        while index < score.masterBars.count, guardCount < 100_000 {
            guardCount += 1
            let bar = score.masterBars[index]
            if bar.isRepeatStart && !cameBack {
                repeatStart = index
                pass = 1
            }
            cameBack = false
            if !bar.alternateEndings.isEmpty && !bar.alternateEndings.contains(pass) {
                index += 1
                continue
            }
            order.append(index)
            if bar.repeatCount > 0 && pass < bar.repeatCount {
                pass += 1
                index = repeatStart
                cameBack = true
            } else {
                index += 1
            }
        }
        return order
    }

    /// One channel per string where there are enough (pitch bends then only move that string), skipping the
    /// drum channel; otherwise one per track.
    static func channels(for score: TabScore) -> [[Int]] {
        let available = Array(0..<16).filter { $0 != 9 }
        let strings = score.tracks.reduce(0) { $0 + $1.stringCount }
        var next = 0
        return score.tracks.map { track in
            if strings <= available.count {
                defer { next += track.stringCount }
                return (0..<track.stringCount).map { available[next + $0] }
            }
            let channel = available[min(next, available.count - 1)]
            next += 1
            return Array(repeating: channel, count: track.stringCount)
        }
    }

    /// The pitch a note sounds: harmonics at the harmonic's pitch, everything else at its fret.
    static func sounds(_ note: TabNote, on track: TabTrack) -> Int {
        guard let harmonic = note.harmonic else { return track.pitch(string: note.string, fret: note.fret) }
        let open = track.pitch(string: note.string, fret: 0)
        switch harmonic {
        case .natural:
            let above = [12: 12, 24: 24, 7: 19, 19: 19, 5: 24, 4: 28, 9: 28, 16: 28, 3: 31, 2: 36][note.fret] ?? note.fret + 12
            return open + above
        case .artificial, .pinch, .tapped, .semi:
            return track.pitch(string: note.string, fret: note.fret) + 12
        }
    }

    /// The bend at a point along the note, between its curve's points.
    static func cents(_ bend: TabNote.Bend, at position: Double) -> Int {
        guard let first = bend.points.first else { return 0 }
        guard position > first.position else { return first.cents }
        for (a, b) in zip(bend.points, bend.points.dropFirst()) where position <= b.position {
            let fraction = (position - a.position) / max(b.position - a.position, 0.0001)
            return Int(Double(a.cents) + Double(b.cents - a.cents) * fraction)
        }
        return bend.points.last!.cents
    }

    static func bendValue(cents: Int) -> Int {
        let semitones = Double(cents) / 100
        return min(16383, max(0, 8192 + Int(semitones / Double(bendRange) * 8191)))
    }

    // MARK: - Reading it back

    /// Where a track is at a time (the last beat that started), for following playback.
    public func position(of track: Int, at time: Double) -> Moment? {
        guard moments.indices.contains(track) else { return nil }
        let moments = self.moments[track]
        var low = 0, high = moments.count - 1
        var found: Moment?
        while low <= high {
            let middle = (low + high) / 2
            if moments[middle].time <= time + 0.0005 {
                found = moments[middle]
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }

    /// When a bar (and beat) is first played, to start from there.
    public func time(of position: TabPosition, track: Int) -> Double {
        guard moments.indices.contains(track) else { return 0 }
        if let moment = moments[track].first(where: { $0.bar == position.bar && $0.beat >= position.beat }) {
            return moment.time
        }
        return bars.first { $0.bar == position.bar }?.time ?? 0
    }

    /// "bar.beat" at a time, e.g. "3.2".
    public func barAndBeat(at time: Double) -> (bar: Int, beat: Int)? {
        guard let bar = bars.last(where: { $0.time <= time + 0.0005 }) else { return nil }
        return (bar.bar + 1, Int((time - bar.time) / max(bar.beatSeconds, 0.0001)) + 1)
    }
}
