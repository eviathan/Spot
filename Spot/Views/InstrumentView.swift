//
//  InstrumentView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI
import SpotCore

struct InstrumentView: View {
    @Environment(UIState.self) private var ui
    @Environment(SequenceSession.self) private var session
    
    var body: some View {
        switch ui.tab {
        case .Library: LibraryFretboard()
        case .Tab: TabFretboard()
        case .Sequence:
            if let sequence = session.sequence, let editor = session.editor {
                SequencerFretboard(sequence: sequence, editor: editor)
            }
        case .Settings: EmptyView()
        }
    }
}

/// The Library tab's fretboard: the selected scale/chord, its current shape, or a shape being drawn.
struct LibraryFretboard: View {
    @Environment(SelectionState.self) private var selection
    @Environment(DisplaySettings.self) private var display
    @Environment(PlaybackController.self) private var playback
    @Environment(\.theme) private var theme

    var body: some View {
        let fretboard = selection.fretboard
        // While drawing a shape, show the draft and let clicks add or remove notes
        let isDrawing = selection.shapeDraft != nil
        let shape = isDrawing ? selection.draftPositions : selection.currentShape?.positions(root: selection.root, on: fretboard)

        let markers = FretMarker.build(fretboard: fretboard,
                                       root: selection.spelledRoot,
                                       formula: selection.formula,
                                       key: selection.key,
                                       shape: shape)
            .map { marker -> FretboardMarker in
                let isHighlighted = (display.highlightAllPositions && !isDrawing) || marker.isInPosition
                let isVisible = display.isolatePosition && !isDrawing
                    ? isHighlighted
                    : !display.hideUnrelatedNotes || marker.isInCollection
                guard marker.isInCollection else {
                    return .unrelated(marker, label: label(for: marker), theme: theme, isVisible: isVisible)
                }
                // As on every fretboard: a chord or interval's notes solid, a scale's ringed with a black middle,
                // the root a square, and notes away from the shape faint
                return FretboardMarker(marker, label: label(for: marker),
                                       tone: selection.kind == .scale ? .scale : .chord,
                                       semitones: marker.semitonesAboveRoot,
                                       prominence: isHighlighted ? .full : .faint,
                                       theme: theme, isVisible: isVisible,
                                       canSetFinger: isDrawing && marker.isInPosition)
            }

        // While a shape is being heard: each note lit as it sounds
        let audition = playback.audition
        TimelineView(.animation(minimumInterval: 1 / 60, paused: audition == nil)) { context in
            FretboardView(fretboard: fretboard,
                          markers: audition.map { lit(markers, $0.intensity(at: context.date)) } ?? markers,
                          onTap: { marker in
                              if isDrawing {
                                  selection.toggleDraftNote(at: marker.position)
                              } else {
                                  selection.root = marker.pitchClass
                              }
                          },
                          onSetFinger: { marker, finger in selection.setDraftFinger(finger, at: marker.position) })
        }
        // Something else picked (another chord or scale, root or shape): what was playing stops
        .onChange(of: "\(selection.selectedId)|\(selection.root.value)|\(selection.currentShapeIndex ?? -1)") {
            playback.stopAudition()
        }
    }

    /// Notes sounding: a little bigger, with a white ring, as much as they're lit.
    private func lit(_ markers: [FretboardMarker], _ intensity: [FretPosition: Double]) -> [FretboardMarker] {
        guard !intensity.isEmpty else { return markers }
        return markers.map { marker in
            guard let level = intensity[marker.marker.position], level > 0 else { return marker }
            var lit = marker
            lit.scale *= 1 + 0.3 * level
            lit.halo = Color.white.opacity(level)
            lit.haloWidth = 3
            lit.sounding = level
            lit.haloDashed = false
            return lit
        }
    }

    private func label(for marker: FretMarker) -> String {
        switch display.markerLabel {
        case .interval: return marker.intervalName
        case .note: return marker.noteName.description
        case .finger: return marker.finger.map(String.init) ?? marker.intervalName
        }
    }
}

struct InstrumentView_Previews: PreviewProvider {
    static var previews: some View {
        InstrumentView()
    }
}

/// The Tab tab's fretboard: the notes in the beat at the cursor (in the track's tuning, capo included), named as
/// notes. In the sequence's tab they look as on the sequence's fretboard, by their interval to the chord there
/// (solid if in the chord, ringed if in its scale); otherwise plain, the cursor's string picked out.
struct TabFretboard: View {
    @Environment(TabSession.self) private var session
    @Environment(TransportState.self) private var transport
    @Environment(\.theme) private var theme

    var body: some View {
        let track = session.score.flatMap { score in
            session.editor.flatMap { score.tracks.indices.contains($0.track) ? score.tracks[$0.track] : nil }
        }
        let fretboard = Fretboard(tuning: track?.tuning ?? .standard)
        FretboardView(fretboard: fretboard, markers: markers(track: track, on: fretboard))
    }

    /// The sequence's chord (and its scale) at the beat being played or at the cursor.
    private var harmony: (chord: ChordSymbol, scale: ScaleDefinition?)? {
        guard let sequenceSession = session.linkedSequence, let sequence = sequenceSession.sequence,
              let editor = sequenceSession.editor else { return nil }
        let beat = sequenceSession.isPlaying ? transport.position() : session.cursorBeat
        guard let beat, let region = sequence.chord(at: max(beat, 0)), let chord = editor.analysis.chords[region.id] else { return nil }
        return (chord, editor.analysis.scales[region.id])
    }

    private func markers(track: TabTrack?, on fretboard: Fretboard) -> [FretboardMarker] {
        guard let track, let score = session.score, let editor = session.editor else { return [] }
        // While playing, the beat being played; otherwise the one at the cursor
        let playing = session.playhead.flatMap { playhead -> TabBeat? in
            let beats = score.beats(track: editor.track, bar: playhead.bar)
            return beats.indices.contains(playhead.beat) ? beats[playhead.beat] : nil
        }
        guard let beat = playing ?? editor.beat(in: score) else { return [] }
        let harmony = harmony
        let chordOffsets = harmony.map { Set($0.chord.chord.formula.pitchClassOffsets) } ?? []
        let scaleOffsets = harmony?.scale.map { Set($0.formula.pitchClassOffsets) } ?? []
        return beat.notes.compactMap { note -> FretboardMarker? in
            let position = FretPosition(string: note.string, fret: note.fret + track.capo)
            guard note.string < fretboard.stringCount, position.fret <= fretboard.fretCount else { return nil }
            let pitchClass = fretboard.pitchClass(at: position)
            let name = SpelledNote.conventional(pitchClass)
            let offset = harmony.map { pitchClass.semitones(above: $0.chord.root.pitchClass) } ?? 0
            let marker = FretMarker(position: position, pitchClass: pitchClass, semitonesAboveRoot: offset, degree: nil,
                                    isInPosition: true, finger: nil, noteName: name, intervalName: name.description)
            let label = note.isDead ? "x" : name.description
            let isCursorString = playing == nil && note.string == editor.cursor.string
            var styled: FretboardMarker
            if harmony != nil, chordOffsets.contains(offset) || scaleOffsets.contains(offset) {
                styled = FretboardMarker(marker, label: label, tone: chordOffsets.contains(offset) ? .chord : .scale,
                                         semitones: offset, theme: theme)
            } else {
                // No chord to relate it to (or outside it): plain
                styled = FretboardMarker(marker: marker, label: label, ring: theme.defaultMarkerColor, fill: theme.defaultMarkerColor,
                                         text: theme.fretboardColor)
            }
            // The cursor's string: a ring round it
            if isCursorString {
                styled.halo = theme.fretboardColor
                styled.haloWidth = 2.5
            }
            return styled
        }
    }
}
