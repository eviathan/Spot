//
//  TabLink.swift
//  SpotCore
//

import Foundation

/// A tab file a sequence plays along with. The tab keeps to the sequence's tempo and grid: its quarter notes are
/// the sequence's beats, starting at `startBeat`.
public struct TabLink: Hashable, Codable, Sendable {
    /// Security-scoped bookmark, so the file can be found again after it moves.
    public var bookmark: Data?
    public var lastKnownPath: String
    public var fileName: String
    /// The track that plays (and whose chord names can become the sequence's chords); `allTracks` for every one.
    public var track: Int
    /// The sequence beat the tab's first bar starts on.
    public var startBeat: Double
    public var isMuted: Bool

    public init(bookmark: Data?, lastKnownPath: String, fileName: String, track: Int = 0, startBeat: Double = 0,
                isMuted: Bool = false) {
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.fileName = fileName
        self.track = track
        self.startBeat = startBeat
        self.isMuted = isMuted
    }

    public static let allTracks = -1

    /// The name to show, without ".spottab".
    public var name: String {
        (fileName as NSString).deletingPathExtension
    }
}

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
}
