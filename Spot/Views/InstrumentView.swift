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

    var body: some View {
        switch ui.tab {
        case .Library: LibraryFretboard()
        case .Practice: PracticeFretboard()
        case .Sequence, .Settings: EmptyView()
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
