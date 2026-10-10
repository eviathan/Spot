//
//  TabChords.swift
//  SpotCore
//

import Foundation

/// A tab's timing in quarter notes, as a sequence plays it, and its chord names.
extension TabScore {
    /// Where a track's chord names change, in quarter notes from the start as the tab plays (repeats and
    /// endings followed), each lasting until the next or the end. A name repeated straight after itself carries on.
    public func chordChanges(track: Int) -> [(range: BeatRange, name: String)] {
        guard tracks.indices.contains(track) else { return [] }
        let performance = TabPerformance.make(self, inQuarterNotes: true)
        var changes: [(start: Double, name: String)] = []
        for moment in performance.moments[track] {
            let beats = self.beats(track: track, bar: moment.bar)
            guard beats.indices.contains(moment.beat), let name = beats[moment.beat].chord?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty, name != changes.last?.name else { continue }
            changes.append((moment.time, name))
        }
        return changes.enumerated().map { index, change in
            let end = index + 1 < changes.count ? changes[index + 1].start : performance.length
            return (BeatRange(change.start, end), change.name)
        }
    }

    /// How long the tab plays for, in quarter notes (repeats followed).
    public var lengthInQuarterNotes: Double {
        TabPerformance.make(self, inQuarterNotes: true).length
    }

    /// Where the last bar with anything in it ends, in quarter notes as played (empty bars after it don't count).
    public var contentQuarterNotes: Double {
        var time = 0, end = 0
        for bar in TabPerformance.playingOrder(self) {
            time += masterBars[bar].timeSignature.ticks
            if tracks.contains(where: { $0.bars.indices.contains(bar) && !$0.bars[bar].isEmpty }) {
                end = time
            }
        }
        return Double(end) / Double(TabDuration.ticksPerQuarter)
    }
}
