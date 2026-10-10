//
//  SequencerFretboard.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Where the playhead is in a sequence window: the live position while it plays, otherwise the selection.
func sequencePosition(_ editor: SequenceEditorState, _ playback: PlaybackController, _ transport: TransportState) -> Double {
    playback.playingSequence == editor.id ? transport.position() : editor.selection.start
}

/// The current chord and its scale, with the next chord fading in just before it arrives.
struct SequencerFretboard: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(DisplaySettings.self) private var display
    @Environment(\.theme) private var theme

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            FretboardView(fretboard: editor.fretboard,
                          markers: markers(at: sequencePosition(editor, playback, transport), time: context.date),
                          onTap: { marker in playback.previewNote(editor.fretboard.midiNote(at: marker.position)) })
        }
    }

    private func markers(at position: Double, time: Date) -> [FretboardMarker] {
        let fretboard = editor.fretboard
        let analysis = editor.analysis

        guard let region = sequence.chord(at: max(position, 0)) ?? sequence.chord(after: position),
              let chord = analysis.chords[region.id] else { return [] }

        let scale = analysis.scales[region.id]
        let roles = scale.map { ChordScaleMatcher.roles(chord: chord.chord, scale: $0) }
            ?? Dictionary(uniqueKeysWithValues: (0..<12).map { ($0, chord.chord.formula.pitchClassOffsets.contains($0) ? NoteRole.chordTone : .outside) })

        // The next chord, faded in over the last few beats before it starts
        let nextRegion = sequence.chord(after: max(position, region.range.start))
        let nextChord = nextRegion.flatMap { analysis.chords[$0.id] }
        var ghost = 0.0
        if let nextRegion, nextChord != nil {
            let beatsLeft = nextRegion.range.start - position
            if beatsLeft > 0 && beatsLeft <= editor.ghostBeats {
                ghost = 1 - beatsLeft / editor.ghostBeats
            }
        }
        let nextTones = Set(nextChord.map { $0.chord.formula.pitchClasses(from: $0.root.pitchClass) } ?? [])
        // Where to land: the next chord's 3rd and 7th
        let targets = Set(nextChord.map { next in
            next.chord.formula.degrees.filter { [2, 6].contains($0.letterSteps) }.map { next.root.pitchClass.transposed(by: $0.semitones) }
        } ?? [])
        let pulse = 0.85 + 0.15 * (0.5 + 0.5 * sin(time.timeIntervalSinceReferenceDate * .pi * 4))

        let chordDegrees = Dictionary(chord.chord.formula.degrees.map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let scaleDegrees = Dictionary((scale?.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let nextDegrees = Dictionary((nextChord?.chord.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let key = analysis.key ?? Key(conventional: chord.root.pitchClass, .major)

        return fretboard.allPositions.map { position in
            let pitchClass = fretboard.pitchClass(at: position)
            let offset = pitchClass.semitones(above: chord.root.pitchClass)
            let role = roles[offset] ?? .outside
            let isNextTone = ghost > 0 && nextTones.contains(pitchClass)

            // Notes only in the next chord are named from its root
            let degree: Degree?
            let root: SpelledNote
            if role == .outside && isNextTone, let nextChord {
                root = nextChord.root
                degree = nextDegrees[pitchClass.semitones(above: nextChord.root.pitchClass)]
            } else {
                root = chord.root
                degree = chordDegrees[offset] ?? scaleDegrees[offset].map(ChordScaleMatcher.tensionName)
            }
            let semitones = pitchClass.semitones(above: root.pitchClass)
            let marker = FretMarker(position: position, pitchClass: pitchClass, semitonesAboveRoot: semitones,
                                    degree: degree, isInPosition: true, finger: nil,
                                    noteName: degree.map(root.spelling) ?? key.spell(pitchClass),
                                    intervalName: degree?.intervalName ?? Degree.chromaticIntervalName(semitones))
            let label = display.markerLabel == .note ? marker.noteName.description : marker.intervalName

            switch role {
            case .chordTone:
                return FretboardMarker(marker: marker, label: label, ring: roleColour(.chordTone), fill: .black, text: .white,
                                       halo: isNextTone ? Color.white.opacity(ghost) : nil)
            case .tension, .avoid:
                return FretboardMarker(marker: marker, label: label, ring: roleColour(role), fill: theme.defaultMarkerColor,
                                       text: theme.fretboardColor, scale: 0.8,
                                       halo: isNextTone ? theme.chordToneColor.opacity(ghost) : nil)
            case .outside:
                return FretboardMarker(marker: marker, label: label, ring: theme.chordToneColor, fill: .black.opacity(0.4),
                                       text: .white, isVisible: isNextTone,
                                       scale: targets.contains(pitchClass) ? pulse : 0.8,
                                       opacity: ghost)
            }
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
}

/// Big readout of the chord now, the next one and how long until it arrives.
struct NowNextView: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { _ in
            let position = sequencePosition(editor, playback, transport)
            let region = sequence.chord(at: max(position, 0))
            let next = sequence.chord(after: max(position, region?.range.start ?? position))
            let beatInBar = Int(floor(position)) - Int(floor(position / Double(sequence.beatsPerBar))) * sequence.beatsPerBar

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPlaying && position < editor.selection.start ? "Count-in" : (sequence.section(at: max(position, 0))?.name ?? " "))
                        .font(.caption)
                        .opacity(0.6)
                    Text(region.map(display) ?? "–")
                        .font(.system(size: 34, weight: .bold))
                    if let region, let scale = editor.analysis.scales[region.id], let chord = editor.analysis.chords[region.id] {
                        Text(chord.root.description + " " + scale.name)
                            .font(.callout)
                            .opacity(0.7)
                    }
                }
                .frame(minWidth: 220, alignment: .leading)

                // The beats of the current bar
                HStack(spacing: 8) {
                    ForEach(0..<sequence.beatsPerBar, id: \.self) { beat in
                        Circle()
                            .fill(isPlaying && beat == beatInBar ? Color.white : Color.white.opacity(0.2))
                            .frame(width: beat == 0 ? 14 : 10, height: beat == 0 ? 14 : 10)
                    }
                }

                if let next {
                    let beatsLeft = Int(ceil(next.range.start - position))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next")
                            .font(.caption)
                            .opacity(0.6)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(display(next))
                                .font(.system(size: 24, weight: .semibold))
                            Text(beatsLeft == 1 ? "in 1 beat" : "in \(beatsLeft) beats")
                                .font(.callout)
                                .foregroundColor(beatsLeft <= Int(editor.ghostBeats) && isPlaying ? .orange : .white.opacity(0.7))
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func display(_ region: ChordRegion) -> String {
        editor.analysis.chords[region.id]?.description ?? region.symbol
    }
}
