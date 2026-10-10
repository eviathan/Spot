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
                          // Clicking a fret moves the hand there (⌥-click plays the note)
                          onTap: { marker in editor.handFret = max(1, marker.position.fret) })
        }
    }

    /// The current chord's scale, coloured by role, and the next chord as small tags beside its notes,
    /// so the two never get mixed up.
    private func markers(at position: Double, time: Date) -> [FretboardMarker] {
        let fretboard = editor.fretboard
        let analysis = editor.analysis

        guard let region = sequence.chord(at: max(position, 0)) ?? sequence.chord(after: position),
              let chord = analysis.chords[region.id] else { return [] }

        let scale = analysis.scales[region.id]
        let roles = scale.map { ChordScaleMatcher.roles(chord: chord.chord, scale: $0) }
            ?? Dictionary(uniqueKeysWithValues: (0..<12).map { ($0, chord.chord.formula.pitchClassOffsets.contains($0) ? NoteRole.chordTone : .outside) })

        // Following the hand: only the chosen position for each chord, rather than the whole neck
        let currentPlacement = analysis.positions[region.id]?.placement
        let followsHand = editor.neckView == .followHand && currentPlacement != nil

        // The next chord: where the hand goes for it, its notes named from its own root, and stronger as it nears
        let nextRegion = sequence.chord(after: max(position, region.range.start))
        let nextChord = nextRegion.flatMap { analysis.chords[$0.id] }
        let nextPlacement = nextRegion.flatMap { analysis.positions[$0.id]?.placement }
        var nearness = 0.0
        if let nextRegion {
            let beatsLeft = nextRegion.range.start - position
            nearness = beatsLeft <= 0 ? 1 : max(0, 1 - beatsLeft / max(editor.ghostBeats, 0.5))
        }
        let nextDegrees = Dictionary((nextChord?.chord.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) },
                                     uniquingKeysWith: { first, _ in first })

        let chordDegrees = Dictionary(chord.chord.formula.degrees.map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let scaleDegrees = Dictionary((scale?.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let key = analysis.key ?? Key(conventional: chord.root.pitchClass, .major)

        return fretboard.allPositions.map { position in
            let pitchClass = fretboard.pitchClass(at: position)
            let offset = pitchClass.semitones(above: chord.root.pitchClass)
            let role = roles[offset] ?? .outside
            let inCurrent = !followsHand || currentPlacement?[position] != nil

            let degree = chordDegrees[offset] ?? scaleDegrees[offset].map(ChordScaleMatcher.tensionName)
            let marker = FretMarker(position: position, pitchClass: pitchClass, semitonesAboveRoot: offset,
                                    degree: degree, isInPosition: true, finger: nil,
                                    noteName: degree.map(chord.root.spelling) ?? key.spell(pitchClass),
                                    intervalName: degree?.intervalName ?? Degree.chromaticIntervalName(offset))
            let label = display.markerLabel == .note ? marker.noteName.description : marker.intervalName

            var tag: FretTag?
            // Only where the hand goes for it (everywhere only if there's no position for it), to keep the neck readable
            if let nextChord, nextPlacement.map({ $0[position] != nil }) ?? true,
               let nextDegree = nextDegrees[pitchClass.semitones(above: nextChord.root.pitchClass)] {
                // Its 3rd and 7th are the notes to aim for
                let isTarget = [2, 6].contains(nextDegree.letterSteps)
                tag = FretTag(label: display.markerLabel == .note ? nextChord.root.spelling(nextDegree).description : nextDegree.intervalName,
                              color: nextChordColour, emphasis: nearness, isStrong: isTarget)
            }

            switch role {
            case .chordTone where inCurrent:
                return FretboardMarker(marker: marker, label: label, ring: roleColour(.chordTone), fill: .black, text: .white, tag: tag)
            case .chordTone:
                // Chord tones elsewhere on the neck, faint, for orientation
                return FretboardMarker(marker: marker, label: label, ring: roleColour(.chordTone), fill: .black, text: .white,
                                       scale: 0.55, opacity: 0.35, tag: tag)
            case .tension, .avoid:
                return FretboardMarker(marker: marker, label: label, ring: roleColour(role), fill: theme.defaultMarkerColor,
                                       text: theme.fretboardColor, isVisible: inCurrent, scale: 0.8, tag: tag)
            case .outside:
                return FretboardMarker(marker: marker, label: label, ring: theme.chordToneColor, fill: .black.opacity(0.4),
                                       text: .white, isVisible: false, tag: tag)
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

/// The colour of everything about the next chord: its name here and its tags on the fretboard.
let nextChordColour = Color(red: 0.62, green: 0.36, blue: 0.95)

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

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isPlaying && position < editor.selection.start ? "Count-in" : (sequence.section(at: max(position, 0))?.name ?? " "))
                        .font(.caption2)
                        .opacity(0.6)
                    // Nothing when there's no chord here
                    Text(region.map(display) ?? " ")
                        .font(.system(size: 24, weight: .bold))
                        .lineLimit(1)
                }
                .frame(minWidth: 110, alignment: .leading)

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
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Next")
                            .font(.caption2)
                            .foregroundColor(nextChordColour)
                        // One line, so nothing here changes the row's height
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(display(next))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(nextChordColour)
                                .lineLimit(1)
                            Text(beatsLeft == 1 ? "in 1 beat" : "in \(beatsLeft) beats")
                                .font(.caption)
                                .foregroundColor(beatsLeft <= Int(editor.ghostBeats) && isPlaying ? .orange : .white.opacity(0.7))
                            if let shift = shiftHint(from: region, to: next) {
                                Label(shift.text, systemImage: shift.up ? "arrow.up.right" : "arrow.down.left")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .help("The next chord. On the fretboard its notes are the violet tags, where your hand goes for it.")

                    // The next chord as a small diagram. Off for now: it changed the height of this row as it came and went.
                    // if editor.showsNextDiagram, let chord = editor.analysis.chords[next.id],
                    //    let placement = editor.analysis.positions[next.id]?.placement {
                    //     ChordBoxView(placement: placement, chordTones: Set(chord.chord.formula.pitchClasses(from: chord.root.pitchClass)),
                    //                  root: chord.root.pitchClass, fretboard: editor.fretboard)
                    //         .frame(width: 110, height: 48)
                    //         .help("The next chord's notes in the position to play it")
                    // }
                }
            }
            .frame(height: 40)
        }
    }

    /// "Move up to fret 7" when the next chord's position is a stretch away from the current one.
    private func shiftHint(from current: ChordRegion?, to next: ChordRegion) -> (text: String, up: Bool)? {
        guard editor.neckView == .followHand, let current,
              let from = editor.analysis.positions[current.id], let to = editor.analysis.positions[next.id],
              abs(to.centre - from.centre) >= 2.5 else { return nil }
        let lowest = to.placement.keys.map(\.fret).filter { $0 > 0 }.min() ?? Int(to.centre)
        return to.centre > from.centre ? ("Move up to fret \(lowest)", true) : ("Move down to fret \(lowest)", false)
    }
    
    private func display(_ region: ChordRegion) -> String {
        editor.analysis.chords[region.id]?.description ?? region.symbol
    }
}

/// A small fretboard window (high string at the top, like the main one) with a chord's notes in one position.
struct ChordBoxView: View {
    let placement: [FretPosition: ShapeNote]
    let chordTones: Set<PitchClass>
    let root: PitchClass
    let fretboard: Fretboard
    
    @Environment(\.theme) private var theme
    
    var body: some View {
        let notes = placement.keys.filter { chordTones.contains(fretboard.pitchClass(at: $0)) }
        let fretted = notes.map(\.fret).filter { $0 > 0 }
        let first = max(1, (fretted.min() ?? 1))
        let span = max(4, (fretted.max() ?? first) - first + 1)
        
        Canvas { context, size in
            let strings = fretboard.stringCount
            let labelWidth: CGFloat = 18
            let width = size.width - labelWidth
            let fretWidth = width / CGFloat(span)
            let stringGap = size.height / CGFloat(strings)
            let y = { (string: Int) in (CGFloat(strings - 1 - string) + 0.5) * stringGap }
            
            for string in 0..<strings {
                var line = Path()
                line.move(to: CGPoint(x: labelWidth, y: y(string)))
                line.addLine(to: CGPoint(x: size.width, y: y(string)))
                context.stroke(line, with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
            for fret in 0...span {
                var line = Path()
                let x = labelWidth + CGFloat(fret) * fretWidth
                line.move(to: CGPoint(x: x, y: y(strings - 1)))
                line.addLine(to: CGPoint(x: x, y: y(0)))
                context.stroke(line, with: .color(.white.opacity(fret == 0 && first == 1 ? 0.9 : 0.35)), lineWidth: fret == 0 && first == 1 ? 3 : 1)
            }
            context.draw(Text("\(first)").font(.system(size: 9)).foregroundColor(.white.opacity(0.7)),
                         at: CGPoint(x: labelWidth / 2, y: size.height / 2))
            
            let dot = min(fretWidth, stringGap) * 0.8
            for note in notes {
                let x: CGFloat = note.fret == 0
                    ? labelWidth - 6
                    : labelWidth + (CGFloat(note.fret - first) + 0.5) * fretWidth
                guard note.fret == 0 || (note.fret >= first && note.fret < first + span) else { continue }
                let rect = CGRect(x: x - dot / 2, y: y(note.string) - dot / 2, width: dot, height: dot)
                let isRoot = fretboard.pitchClass(at: note) == root
                context.fill(Circle().path(in: rect), with: .color(isRoot ? theme.avoidColor : theme.chordToneColor))
            }
        }
    }
}

/// The chord under the playhead spelled out twice: the chord's intervals, and its scale's, each with the
/// notes they make. Scale notes are coloured as on the fretboard (chord tone, tension, avoid).
struct ChordScaleIntervals: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(\.theme) private var theme

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id
        // Only needs to change when the chord does; a few times a second is plenty
        TimelineView(.animation(minimumInterval: 1 / 10, paused: !isPlaying)) { _ in
            let position = sequencePosition(editor, playback, transport)
            let region = sequence.chord(at: max(position, 0)) ?? sequence.chord(after: position)
            HStack(spacing: 18) {
                if let region, let chord = editor.analysis.chords[region.id] {
                    group(title: chord.description, degrees: chord.chord.formula.degrees, root: chord.root) { _ in theme.chordToneColor }
                    if let scale = editor.analysis.scales[region.id] {
                        let roles = ChordScaleMatcher.roles(chord: chord.chord, scale: scale)
                        group(title: "\(chord.root) \(scale.name)", degrees: scale.formula.degrees, root: chord.root) { degree in
                            switch roles[degree.pitchClassOffset] ?? .outside {
                            case .chordTone: return theme.chordToneColor
                            case .tension: return theme.tensionColor
                            case .avoid: return theme.avoidColor
                            case .outside: return theme.openMarkerColor
                            }
                        }
                    }
                } else {
                    Text("No chord here")
                        .font(.caption)
                        .opacity(0.5)
                }
                Spacer()
            }
            .frame(height: 34)
            .padding(.horizontal, 16)
        }
    }

    private func group(title: String, degrees: [Degree], root: SpelledNote, colour: @escaping (Degree) -> Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.trailing, 4)
            ForEach(Array(degrees.enumerated()), id: \.offset) { _, degree in
                VStack(spacing: 0) {
                    Text(degree.intervalName)
                        .font(.system(size: 12, weight: .bold))
                    Text(root.spelling(degree).description)
                        .font(.system(size: 10))
                        .opacity(0.8)
                }
                .frame(minWidth: 24)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).stroke(colour(degree), lineWidth: 1.5))
            }
        }
    }
}
