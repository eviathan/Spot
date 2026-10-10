//
//  PracticeFretboard.swift
//  Spot
//

import SwiftUI
import SpotCore

/// The Chord Practice fretboard: the chord voicing, with the chosen scale or arpeggio around it.
struct PracticeFretboard: View {
    @Environment(PracticeState.self) private var practice
    @Environment(DisplaySettings.self) private var display
    @Environment(PlaybackController.self) private var playback
    @Environment(\.theme) private var theme

    var body: some View {
        let fretboard = practice.fretboard
        FretboardView(fretboard: fretboard,
                      markers: markers(on: fretboard),
                      onTap: { marker in playback.previewNote(fretboard.midiNote(at: marker.position)) })
    }

    private func markers(on fretboard: Fretboard) -> [FretboardMarker] {
        guard let chord = practice.current else { return [] }

        let root = chord.root
        let roles = practice.roles
        let voicing = practice.voicingPlacement ?? [:]
        let focus = practice.focusPlacement?.placement
        let focusOffsets = practice.focusOffsets
        let chordDegrees = Dictionary(chord.chord.formula.degrees.map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let scaleDegrees = Dictionary((practice.scale?.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let key = practice.key ?? Key(conventional: root.pitchClass, .major)

        return fretboard.allPositions.map { position in
            let pitchClass = fretboard.pitchClass(at: position)
            let offset = pitchClass.semitones(above: root.pitchClass)
            let role = roles[offset] ?? .outside

            // Name notes from the chord: chord tones by their degree, scale notes as tensions (9, 11, 13)
            let degree = chordDegrees[offset] ?? scaleDegrees[offset].map(ChordScaleMatcher.tensionName)
            let marker = FretMarker(position: position,
                                    pitchClass: pitchClass,
                                    semitonesAboveRoot: offset,
                                    degree: degree,
                                    isInPosition: voicing[position] != nil || focus?[position] != nil,
                                    finger: voicing[position]?.finger ?? focus?[position]?.finger,
                                    noteName: degree.map(root.spelling) ?? key.spell(pitchClass),
                                    intervalName: degree?.intervalName ?? Degree.chromaticIntervalName(offset))

            let colour = practice.colourByRole ? roleColour(role) : theme.intervalColors[offset]

            if voicing[position] != nil {
                return FretboardMarker(marker: marker, label: label(marker), ring: colour, fill: .black, text: .white)
            }

            let inFocus = focus.map { $0[position] != nil } ?? focusOffsets.contains(offset)
            return FretboardMarker(marker: marker,
                                   label: label(marker),
                                   ring: colour,
                                   fill: theme.defaultMarkerColor,
                                   text: theme.fretboardColor,
                                   isVisible: inFocus,
                                   scale: 0.85)
        }
    }

    private func roleColour(_ role: NoteRole) -> Color {
        switch role {
        case .chordTone: return theme.chordToneColor
        case .tension: return theme.tensionColor
        case .avoid: return theme.avoidColor
        case .outside: return theme.openMarkerColor
        }
    }

    private func label(_ marker: FretMarker) -> String {
        switch display.markerLabel {
        case .interval: return marker.intervalName
        case .note: return marker.noteName.description
        case .finger: return marker.finger.map(String.init) ?? marker.intervalName
        }
    }
}
