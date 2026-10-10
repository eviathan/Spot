//
//  TabEditorState.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

/// Where you are in a tab: which track is showing, and the cursor (a string at a beat in a bar).
/// The tab itself lives in `TabSession`.
@Observable
final class TabEditorState {
    struct Cursor: Hashable {
        var bar = 0
        /// Index into the bar's first voice; equal to its beat count for the empty slot after the last beat.
        var beat = 0
        /// 0 is the lowest string.
        var string = 0
    }

    var track = 0
    var cursor = Cursor()
    /// The other end of a selected run of beats (the cursor is one end); nil for none.
    var selectionAnchor: Cursor?
    /// The note value new beats get (and that the toolbar shows).
    var duration = TabDuration(.quarter)
    /// Horizontal spacing: 1 is normal.
    var zoom: Double = 1

    /// A digit just typed, so a second one quickly after makes a two-digit fret.
    @ObservationIgnored var pendingDigit: (fret: Int, time: Date, at: Cursor)?
    /// Copied beats.
    @ObservationIgnored var clipboard: [TabBeat] = []

    var position: TabPosition {
        TabPosition(bar: cursor.bar, beat: cursor.beat)
    }

    /// The selected run of beats, first to last, if there is one.
    var selection: (start: TabPosition, end: TabPosition)? {
        guard let selectionAnchor else { return nil }
        let anchor = TabPosition(bar: selectionAnchor.bar, beat: selectionAnchor.beat)
        return anchor <= position ? (anchor, position) : (position, anchor)
    }

    func zoom(by factor: Double) {
        zoom = min(max(zoom * factor, 0.5), 3)
    }

    /// The beat under the cursor, if there is one.
    func beat(in score: TabScore) -> TabBeat? {
        guard score.tracks.indices.contains(track), score.tracks[track].bars.indices.contains(cursor.bar) else { return nil }
        let beats = score.tracks[track].bars[cursor.bar].voices[0].beats
        return beats.indices.contains(cursor.beat) ? beats[cursor.beat] : nil
    }

    /// Keeps the cursor on something that exists after the tab changes (a track or bar removed, say).
    func clamp(to score: TabScore) {
        track = min(max(track, 0), max(score.tracks.count - 1, 0))
        guard score.tracks.indices.contains(track) else { return }
        let bars = score.tracks[track].bars
        cursor.bar = min(max(cursor.bar, 0), max(bars.count - 1, 0))
        let beats = bars.indices.contains(cursor.bar) ? bars[cursor.bar].voices[0].beats.count : 0
        cursor.beat = min(max(cursor.beat, 0), beats)
        cursor.string = min(max(cursor.string, 0), max(score.tracks[track].stringCount - 1, 0))
    }
}
