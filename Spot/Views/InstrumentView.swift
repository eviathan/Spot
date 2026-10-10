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
                let baseColor = marker.isOpenString ? theme.openMarkerColor : theme.defaultMarkerColor
                let ring = isHighlighted && marker.isInCollection ? theme.intervalColors[marker.semitonesAboveRoot] : baseColor

                return FretboardMarker(marker: marker,
                                       label: label(for: marker),
                                       ring: ring,
                                       fill: marker.isInCollection ? .black : ring,
                                       text: marker.isInCollection || marker.isOpenString ? .white : theme.fretboardColor,
                                       isVisible: isVisible,
                                       canSetFinger: isDrawing && marker.isInPosition)
            }

        FretboardView(fretboard: fretboard,
                      markers: markers,
                      onTap: { marker in
                          if isDrawing {
                              selection.toggleDraftNote(at: marker.position)
                          } else {
                              selection.root = marker.pitchClass
                          }
                      },
                      onSetFinger: { marker, finger in selection.setDraftFinger(finger, at: marker.position) })
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

/// The Tab tab's fretboard: the notes in the beat at the cursor (in the track's tuning, capo included),
/// named as notes, with the cursor's string picked out.
struct TabFretboard: View {
    @Environment(TabSession.self) private var session
    @Environment(\.theme) private var theme

    var body: some View {
        let track = session.score.flatMap { score in
            session.editor.flatMap { score.tracks.indices.contains($0.track) ? score.tracks[$0.track] : nil }
        }
        let fretboard = Fretboard(tuning: track?.tuning ?? .standard)
        FretboardView(fretboard: fretboard, markers: markers(track: track, on: fretboard))
    }

    private func markers(track: TabTrack?, on fretboard: Fretboard) -> [FretboardMarker] {
        guard let track, let score = session.score, let editor = session.editor else { return [] }
        // While playing, the beat being played; otherwise the one at the cursor
        let playing = session.playhead.flatMap { playhead -> TabBeat? in
            let beats = score.beats(track: editor.track, bar: playhead.bar)
            return beats.indices.contains(playhead.beat) ? beats[playhead.beat] : nil
        }
        guard let beat = playing ?? editor.beat(in: score) else { return [] }
        return beat.notes.compactMap { note -> FretboardMarker? in
            let position = FretPosition(string: note.string, fret: note.fret + track.capo)
            guard note.string < fretboard.stringCount, position.fret <= fretboard.fretCount else { return nil }
            let pitchClass = fretboard.pitchClass(at: position)
            let name = SpelledNote.conventional(pitchClass)
            let marker = FretMarker(position: position, pitchClass: pitchClass, semitonesAboveRoot: 0, degree: nil,
                                    isInPosition: true, finger: nil, noteName: name, intervalName: name.description)
            let isCursorString = playing == nil && note.string == editor.cursor.string
            return FretboardMarker(marker: marker, label: note.isDead ? "x" : name.description,
                                   ring: theme.chordToneColor, fill: isCursorString ? theme.chordToneColor : .black,
                                   text: isCursorString ? .black : .white)
        }
    }
}
