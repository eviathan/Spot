//
//  TabEditing.swift
//  SpotCore
//

import Foundation

/// A place in a track: a bar and a beat in its first voice. `beat` can be one past the last beat: the slot
/// where a new beat goes.
public struct TabPosition: Hashable, Comparable, Sendable {
    public var bar: Int
    public var beat: Int

    public init(bar: Int, beat: Int) {
        self.bar = bar
        self.beat = beat
    }

    public static func < (lhs: TabPosition, rhs: TabPosition) -> Bool {
        (lhs.bar, lhs.beat) < (rhs.bar, rhs.beat)
    }
}

/// Editing a track's notes and the bars, as the tab editor does it. Everything works on the first voice.
extension TabScore {
    public func beats(track: Int, bar: Int) -> [TabBeat] {
        guard tracks.indices.contains(track), tracks[track].bars.indices.contains(bar) else { return [] }
        return tracks[track].bars[bar].voices[0].beats
    }

    private mutating func setBeats(_ beats: [TabBeat], track: Int, bar: Int) {
        guard tracks.indices.contains(track), tracks[track].bars.indices.contains(bar) else { return }
        tracks[track].bars[bar].voices[0].beats = beats
    }

    // MARK: Bar lengths

    /// How much of the bar the track's beats fill, in ticks.
    public func ticks(track: Int, bar: Int) -> Int {
        beats(track: track, bar: bar).reduce(0) { $0 + $1.duration.ticks }
    }

    /// How far the track's beats are from filling the bar: negative if short, positive if over, 0 if right
    /// (or if the bar is empty, which counts as a full-bar rest).
    public func fill(track: Int, bar: Int) -> Int {
        guard masterBars.indices.contains(bar), !beats(track: track, bar: bar).isEmpty else { return 0 }
        return ticks(track: track, bar: bar) - masterBars[bar].timeSignature.ticks
    }

    public func isFull(track: Int, bar: Int) -> Bool {
        masterBars.indices.contains(bar) && ticks(track: track, bar: bar) >= masterBars[bar].timeSignature.ticks
    }

    // MARK: Notes and beats

    /// Puts a fret on a string at a beat (replacing what was on that string). At the slot after the last beat,
    /// adds a beat of `duration` first. Returns the beat's index.
    @discardableResult
    public mutating func setNote(track: Int, at position: TabPosition, string: Int, fret: Int, duration: TabDuration) -> Int {
        var beats = beats(track: track, bar: position.bar)
        var index = position.beat
        if index >= beats.count {
            beats.append(TabBeat(duration: duration))
            index = beats.count - 1
        }
        let note = beats[index].notes.first { $0.string == string }
        var updated = note ?? TabNote(string: string, fret: fret)
        updated.fret = fret
        updated.isDead = false
        beats[index].notes.removeAll { $0.string == string }
        beats[index].notes.append(updated)
        beats[index].notes.sort { $0.string < $1.string }
        setBeats(beats, track: track, bar: position.bar)
        return index
    }

    /// Takes the note off a string; the beat becomes a rest if it was the only one.
    public mutating func removeNote(track: Int, at position: TabPosition, string: Int) {
        var beats = beats(track: track, bar: position.bar)
        guard beats.indices.contains(position.beat) else { return }
        beats[position.beat].notes.removeAll { $0.string == string }
        setBeats(beats, track: track, bar: position.bar)
    }

    /// Makes a beat a rest (or, at the slot after the last beat, adds a rest of `duration`).
    public mutating func setRest(track: Int, at position: TabPosition, duration: TabDuration) {
        var beats = beats(track: track, bar: position.bar)
        if position.beat >= beats.count {
            beats.append(TabBeat(duration: duration))
        } else {
            beats[position.beat].notes = []
        }
        setBeats(beats, track: track, bar: position.bar)
    }

    /// Adds a rest of `duration` before a beat.
    public mutating func insertBeat(track: Int, at position: TabPosition, duration: TabDuration) {
        var beats = beats(track: track, bar: position.bar)
        beats.insert(TabBeat(duration: duration), at: min(max(position.beat, 0), beats.count))
        setBeats(beats, track: track, bar: position.bar)
    }

    public mutating func removeBeat(track: Int, at position: TabPosition) {
        var beats = beats(track: track, bar: position.bar)
        guard beats.indices.contains(position.beat) else { return }
        beats.remove(at: position.beat)
        setBeats(beats, track: track, bar: position.bar)
    }

    public mutating func setDuration(track: Int, at position: TabPosition, to duration: TabDuration) {
        var beats = beats(track: track, bar: position.bar)
        guard beats.indices.contains(position.beat) else { return }
        beats[position.beat].duration = duration
        setBeats(beats, track: track, bar: position.bar)
    }

    /// Changes one note on a string at a beat (no-op if there's no note there).
    public mutating func updateNote(track: Int, at position: TabPosition, string: Int, _ change: (inout TabNote) -> Void) {
        var beats = beats(track: track, bar: position.bar)
        guard beats.indices.contains(position.beat),
              let index = beats[position.beat].notes.firstIndex(where: { $0.string == string }) else { return }
        change(&beats[position.beat].notes[index])
        setBeats(beats, track: track, bar: position.bar)
    }

    /// Changes a beat (no-op at the slot after the last one).
    public mutating func updateBeat(track: Int, at position: TabPosition, _ change: (inout TabBeat) -> Void) {
        var beats = beats(track: track, bar: position.bar)
        guard beats.indices.contains(position.beat) else { return }
        change(&beats[position.beat])
        setBeats(beats, track: track, bar: position.bar)
    }

    /// Ties the note on a string to the one before it on that string: the same fret, held on rather than struck.
    /// Tying the first note of a bar ties to the last beat of the previous bar.
    public mutating func toggleTie(track: Int, at position: TabPosition, string: Int) {
        let beats = beats(track: track, bar: position.bar)
        guard beats.indices.contains(position.beat) else { return }
        if let note = beats[position.beat].notes.first(where: { $0.string == string }), note.isTied {
            updateNote(track: track, at: position, string: string) { $0.isTied = false }
            return
        }
        // The note it ties to
        let previous: TabNote?
        if position.beat > 0 {
            previous = beats[position.beat - 1].notes.first { $0.string == string }
        } else {
            previous = self.beats(track: track, bar: position.bar - 1).last?.notes.first { $0.string == string }
        }
        guard let previous else { return }
        let index = setNote(track: track, at: position, string: string, fret: previous.fret, duration: beats[position.beat].duration)
        updateNote(track: track, at: TabPosition(bar: position.bar, beat: index), string: string) { $0.isTied = true }
    }

    // MARK: Copy and paste

    /// The beats from one position to another, inclusive, across bars.
    public func beats(track: Int, from start: TabPosition, to end: TabPosition) -> [TabBeat] {
        let (start, end) = start <= end ? (start, end) : (end, start)
        var result: [TabBeat] = []
        for bar in start.bar...end.bar {
            let beats = beats(track: track, bar: bar)
            let first = bar == start.bar ? start.beat : 0
            let last = bar == end.bar ? min(end.beat, beats.count - 1) : beats.count - 1
            guard first <= last, beats.indices.contains(first) else { continue }
            result += beats[first...last]
        }
        return result
    }

    /// Removes the beats from one position to another, inclusive.
    public mutating func removeBeats(track: Int, from start: TabPosition, to end: TabPosition) {
        let (start, end) = start <= end ? (start, end) : (end, start)
        for bar in (start.bar...end.bar).reversed() {
            var beats = beats(track: track, bar: bar)
            let first = bar == start.bar ? start.beat : 0
            let last = bar == end.bar ? min(end.beat, beats.count - 1) : beats.count - 1
            guard first <= last, beats.indices.contains(first) else { continue }
            beats.removeSubrange(first...last)
            setBeats(beats, track: track, bar: bar)
        }
    }

    /// Puts copies of `beats` in before a position (all in that bar; it may then run over).
    public mutating func insertBeats(_ inserted: [TabBeat], track: Int, at position: TabPosition) {
        var beats = beats(track: track, bar: position.bar)
        let copies = inserted.map { beat -> TabBeat in
            var copy = beat
            copy.id = UUID()
            return copy
        }
        beats.insert(contentsOf: copies, at: min(max(position.beat, 0), beats.count))
        setBeats(beats, track: track, bar: position.bar)
    }

    // MARK: Bars

    /// Sets the time signature from a bar onwards, up to the next bar that had a different one.
    public mutating func setTimeSignature(_ signature: TimeSignature, from bar: Int) {
        guard masterBars.indices.contains(bar) else { return }
        let old = masterBars[bar].timeSignature
        var index = bar
        while masterBars.indices.contains(index), index == bar || masterBars[index].timeSignature == old {
            masterBars[index].timeSignature = signature
            index += 1
        }
    }
}
