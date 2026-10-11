//
//  SequencerFretboard.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Where the playhead is in a sequence window: the live position while it plays, otherwise the selection.
func sequencePosition(_ editor: SequenceEditorState, _ playback: PlaybackController, _ transport: TransportState) -> Double {
    playback.playingSequence == editor.id ? transport.position() : editor.playhead
}

/// The current chord and its scale, plus the next chord in lilac: a ring on notes it shares, small markers for new ones.
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

    /// What's under your fingers now and what's coming, in the Library's colours (each interval its own colour,
    /// the root black):
    /// - chord tones solid in their interval's colour; the rest of the scale the same size, ringed in it with a
    ///   black middle; each chord's root a rounded square
    /// - a note you're playing that's in the next chord is half and half: its colour now on the left, and on the
    ///   right the colour of what it becomes there (the 5th turning into the 3rd: half 5th, half 3rd)
    /// - a note new with the next chord (in neither this chord nor its scale) is a dashed ring in its interval's
    ///   colour in the next chord, faintly filled
    /// The next chord fades in over the last beats before it, while playing (stopped, it's shown to plan with).
    private func markers(at position: Double, time: Date) -> [FretboardMarker] {
        let fretboard = editor.fretboard
        let analysis = editor.analysis

        // A pinned chord holds the fretboard, with nothing coming next
        let pinned = editor.pinnedRegion(in: sequence)
        guard let region = pinned ?? sequence.chord(at: max(position, 0)) ?? sequence.chord(after: position),
              let chord = analysis.chords[region.id] else { return [] }

        let scale = analysis.scales[region.id]
        let roles = scale.map { ChordScaleMatcher.roles(chord: chord.chord, scale: $0) }
            ?? Dictionary(uniqueKeysWithValues: (0..<12).map { ($0, chord.chord.formula.pitchClassOffsets.contains($0) ? NoteRole.chordTone : .outside) })

        // Following the hand: only the chosen voicing and scale shape for each chord, rather than the whole neck
        let current = analysis.positions[region.id]
        let currentPlacement = current?.placement
        let currentVoicing = current?.voicing?.placement
        let followsHand = editor.neckView == .followHand && current != nil

        // The next chord: where the hand goes for it, its notes named from its own root, and stronger as it nears
        // (Round to the start of the loop at its end, while looping)
        let upcoming = pinned == nil ? sequence.upcomingChord(at: position) : nil
        let nextRegion = upcoming?.chord
        let nextChord = nextRegion.flatMap { analysis.chords[$0.id] }
        let nextNeck = nextRegion.flatMap { analysis.positions[$0.id] }
        var nearness = 0.0
        if let upcoming {
            let beatsLeft = upcoming.beatsAway
            nearness = beatsLeft <= 0 ? 1 : max(0, 1 - beatsLeft / max(editor.leadUp(in: sequence), 0.5))
        }
        let isPlaying = playback.playingSequence == editor.id
        // Playing: from nothing to full over the last beats; stopped: there to plan the change with
        let nextStrength = isPlaying ? nearness : 1
        let nextDegrees = Dictionary((nextChord?.chord.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) },
                                     uniquingKeysWith: { first, _ in first })
        // ...and the rest of its scale, named as tensions (9, 11, 13)
        let nextScale = editor.showsNextScale ? nextRegion.flatMap { analysis.scales[$0.id] } : nil
        let nextScaleDegrees = Dictionary((nextScale?.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) },
                                          uniquingKeysWith: { first, _ in first })

        let chordDegrees = Dictionary(chord.chord.formula.degrees.map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let scaleDegrees = Dictionary((scale?.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
        let key = analysis.key ?? Key(conventional: chord.root.pitchClass, .major)

        return fretboard.allPositions.map { position in
            let pitchClass = fretboard.pitchClass(at: position)
            let offset = pitchClass.semitones(above: chord.root.pitchClass)
            let role = roles[offset] ?? .outside
            let inVoicing = currentVoicing?[position] != nil
            // Isolating the shape (⌘I): just the voicing and scale shape, even when showing the whole neck
            let isolates = display.isolatePosition && current != nil
            let inCurrent = (!followsHand && !isolates) || currentPlacement?[position] != nil || inVoicing

            let degree = chordDegrees[offset] ?? scaleDegrees[offset].map(ChordScaleMatcher.tensionName)
            let marker = FretMarker(position: position, pitchClass: pitchClass, semitonesAboveRoot: offset,
                                    degree: degree, isInPosition: true, finger: nil,
                                    noteName: degree.map(chord.root.spelling) ?? key.spell(pitchClass),
                                    intervalName: degree?.intervalName ?? Degree.chromaticIntervalName(offset))
            // Fingers come from the voicing for its notes, otherwise from the scale shape
            let finger = (currentVoicing?[position] ?? currentPlacement?[position])?.finger
            let label: String
            switch display.markerLabel {
            case .note: label = marker.noteName.description
            case .finger: label = finger.map { $0 == 0 ? "0" : "\($0)" } ?? marker.intervalName
            case .interval: label = marker.intervalName
            }

            // In the next chord or its scale? Once it's showing: where the hand goes for it, and with shape isolation
            // off, everywhere else on the neck too (faint there, like the rest of what's away from the hand)
            let inNextPosition = nextNeck.map { $0.placement[position] != nil || $0.voicing?.placement[position] != nil } ?? true
            var next: (label: String, offset: Int, isChordTone: Bool)?
            if nextStrength > 0.01, let nextChord, inNextPosition || !isolates {
                let nextOffset = pitchClass.semitones(above: nextChord.root.pitchClass)
                let name = { (degree: Degree) in
                    display.markerLabel == .note ? nextChord.root.spelling(degree).description : degree.intervalName
                }
                if let nextDegree = nextDegrees[nextOffset] {
                    next = (name(nextDegree), nextOffset, true)
                } else if let scaleDegree = nextScaleDegrees[nextOffset] {
                    next = (name(ChordScaleMatcher.tensionName(scaleDegree)), nextOffset, false)
                }
            }
            // Held into the next chord: the right half in the colour of what it becomes there. Only in its scale (with
            // the next scale showing): a dashed ring in that colour instead.
            let becomes = next.flatMap { $0.isChordTone ? theme.intervalColor($0.offset).opacity(nextStrength) : nil }
            let becomesInScale = next.flatMap { $0.isChordTone ? nil : theme.intervalColor($0.offset).opacity(nextStrength * 0.8) }

            switch role {
            case .chordTone where inVoicing || inCurrent, .tension where inCurrent, .avoid where inCurrent:
                // Chord tones solid, the rest of the scale ringed (the voicing full strength, the chord's other notes
                // in the position a little softer, notes to avoid over the chord softer too)
                var styled = FretboardMarker(marker, label: label, tone: role == .chordTone ? .chord : .scale, semitones: offset,
                                             prominence: inVoicing || role == .tension ? .full : .soft, theme: theme)
                styled.split = becomes
                styled.textShadow = becomes != nil
                if becomes != nil { styled.text = .white }
                styled.halo = becomesInScale
                styled.haloDashed = true
                return styled
            default:
                // Elsewhere on the neck (isolating the shape hides these): see-through, but showing what they become
                // in the next chord just the same
                if role != .outside && !isolates {
                    var styled = FretboardMarker(marker, label: label, tone: role == .chordTone ? .chord : .scale, semitones: offset,
                                                 prominence: .faint, theme: theme)
                    styled.split = becomes
                    styled.textShadow = becomes != nil
                    if becomes != nil { styled.text = .white }
                    styled.halo = becomesInScale
                    styled.haloDashed = true
                    return styled
                }
                // New with the next chord: a dashed ring in its interval's colour there, faintly filled (its chord
                // tones; with the next scale showing, its other notes fainter), and see-through away from where the
                // hand goes for it
                if let next {
                    let nextColour = theme.intervalColor(next.offset)
                    let away = inNextPosition ? 1 : 0.5
                    return FretboardMarker(marker: marker, label: next.label, ring: nextColour,
                                           fill: nextColour.opacity(next.isChordTone ? 0.3 : 0.12), text: .white,
                                           scale: next.isChordTone ? 0.9 : 0.7,
                                           opacity: nextStrength * (next.isChordTone ? 1 : 0.8) * away,
                                           isRoot: next.isChordTone && next.offset == 0, ringDashed: true)
                }
                // Everything else: shown plainly (as on the Library tab) when unrelated notes are on (⌘U)
                return unrelatedMarker(marker, label: label)
            }
        }
    }

    private func unrelatedMarker(_ marker: FretMarker, label: String) -> FretboardMarker {
        .unrelated(marker, label: label, theme: theme, isVisible: !display.hideUnrelatedNotes && !display.isolatePosition)
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

/// The colour of everything about the next chord: its name in the header and its notes on the fretboard.
var nextChordColour: Color { ThemeStore.shared.current.nextChord }

/// What to play, read at a glance, in three blocks: the chord now (with its section and the beat), its chord
/// and scale intervals with the notes they make, and the chord coming next. A fixed height, so nothing
/// coming or going moves the rest of the window.
struct PerformanceHeader: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(\.theme) private var theme

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { _ in
            let position = sequencePosition(editor, playback, transport)
            // A pinned chord holds, with nothing coming next
            let pinned = editor.pinnedRegion(in: sequence)
            let region = pinned ?? sequence.chord(at: max(position, 0))
            // (Round to the start of the loop at its end, while looping)
            let upcoming = pinned == nil ? sequence.upcomingChord(at: position) : nil
            let next = upcoming?.chord

            HStack(spacing: 0) {
                now(region, position: position, isPlaying: isPlaying)
                    .frame(width: laneHeaderWidth, alignment: .leading)
                Divider().padding(.vertical, 12)
                intervals(region ?? sequence.chord(after: position))
                    .frame(maxWidth: .infinity, alignment: .leading)
                // MarkerLegend()
                //     .padding(.trailing, 14)
                Divider().padding(.vertical, 12)
                upNext(next, after: region, beatsAway: upcoming?.beatsAway ?? 0, isPlaying: isPlaying)
                    .frame(width: 300, alignment: .leading)
            }
            .frame(height: 86)
            .background(Color.black.opacity(0.18))
        }
    }

    // MARK: Now

    private func now(_ region: ChordRegion?, position: Double, isPlaying: Bool) -> some View {
        let beatInBar = Int(sequence.barAndBeat(at: position).beat)
        // The section (there's no count-in for now, so nothing else goes here)
        let caption = editor.pinnedRegion(in: sequence) != nil ? "Pinned" : sequence.partName(at: max(position, 0))

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                blockTitle("NOW")
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .lineLimit(1)
                        .opacity(0.6)
                }
            }
            Text(region.map(display) ?? "–")
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(region == nil ? 0.3 : 1)
            // The beats of the bar, the first bigger
            // (In the time signature's unit: eighths in 7/8; smaller when there are many)
            let beats = sequence.timeSignature.numerator
            let small: CGFloat = beats > 8 ? 5 : 8
            HStack(spacing: beats > 8 ? 4 : 7) {
                ForEach(0..<beats, id: \.self) { beat in
                    Circle()
                        .fill(isPlaying && beat == beatInBar ? Color.white : Color.white.opacity(0.18))
                        .frame(width: beat == 0 ? small + 3 : small, height: beat == 0 ? small + 3 : small)
                }
            }
            .frame(height: 11)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Intervals

    @ViewBuilder
    private func intervals(_ region: ChordRegion?) -> some View {
        if let region, let chord = editor.analysis.chords[region.id] {
            let scale = editor.analysis.scales[region.id]
            let roles = scale.map { ChordScaleMatcher.roles(chord: chord.chord, scale: $0) } ?? [:]
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    blockTitle("CHORD")
                    Text(chord.description)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                    IntervalChips(degrees: chord.chord.formula.degrees, root: chord.root, colour: { theme.chipColour($0) }, solid: true)
                }
                GridRow {
                    blockTitle("SCALE")
                    Text(scale.map { "\(chord.root.description) \($0.name)" } ?? "–")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 150, alignment: .leading)
                    if let scale {
                        // (Notes to avoid over the chord dimmed)
                        IntervalChips(degrees: scale.formula.degrees, root: chord.root, colour: { theme.chipColour($0) },
                                      dimmed: { roles[$0.pitchClassOffset] == .avoid })
                    }
                }
            }
            .padding(.horizontal, 16)
            .help("The chord's intervals and the scale's, with the notes they make, in the fretboard's colours: chord tones solid, the scale outlined (notes to avoid over the chord dimmed).")
        } else {
            Text("No chord at the playhead")
                .font(.callout)
                .opacity(0.4)
                .padding(.horizontal, 16)
        }
    }

    /// One chip per degree: the interval, and the note it makes from `root`.
    private func chips(_ degrees: [Degree], root: SpelledNote, colour: @escaping (Degree) -> Color) -> some View {
        IntervalChips(degrees: degrees, root: root, colour: colour)
    }

    // MARK: Next

    private func upNext(_ next: ChordRegion?, after region: ChordRegion?, beatsAway: Double, isPlaying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                blockTitle("NEXT")
                    .foregroundColor(nextChordColour)
                if next != nil {
                    let beatsLeft = Int(ceil(beatsAway))
                    Text(beatsLeft == 1 ? "in 1 beat" : "in \(beatsLeft) beats")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(Double(beatsLeft) <= editor.leadUp(in: sequence) && isPlaying ? SpotStyle.warning : SpotStyle.text.opacity(0.6))
                }
            }
            // The chord, and the scale that goes with it
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(next.map(display) ?? "–")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(next == nil ? .white.opacity(0.3) : nextChordColour)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let next, let chord = editor.analysis.chords[next.id], let scale = editor.analysis.scales[next.id] {
                    Text("\(chord.root.description) \(scale.name)")
                        .font(.callout)
                        .foregroundColor(nextChordColour.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            // Always a line here, empty or not, so the block keeps its shape
            Group {
                if let next, let shift = shiftHint(from: region, to: next) {
                    Label(shift.text, systemImage: shift.up ? "arrow.up.right" : "arrow.down.left")
                        .foregroundColor(SpotStyle.warning)
                } else {
                    Text(" ")
                }
            }
            .font(.caption)
            .lineLimit(1)
            .frame(height: 14)
        }
        .padding(.horizontal, 16)
        .help("The next chord and its scale. On the fretboard they're lilac: a ring on notes you're already playing (dashed if only in the scale), a small marker on new ones (hollow if only in the scale).")
    }

    private func blockTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .opacity(0.55)
    }

    /// "Move up to fret 7" when the next chord's position is a stretch away from the current one.
    private func shiftHint(from current: ChordRegion?, to next: ChordRegion) -> (text: String, up: Bool)? {
        guard editor.neckView == .followHand, let current,
              let from = editor.analysis.positions[current.id], let to = editor.analysis.positions[next.id],
              abs(to.centre - from.centre) >= 2.5 else { return nil }
        let lowest = (to.voicing?.placement ?? to.placement).keys.map(\.fret).filter { $0 > 0 }.min() ?? Int(to.centre)
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

/// One chip per degree: the interval, and the note it makes from `root`, outlined in `colour`.
struct IntervalChips: View {
    let degrees: [Degree]
    let root: SpelledNote
    let colour: (Degree) -> Color
    var size: CGFloat = 1
    /// Filled with the colour (chord tones, as on the fretboard); otherwise outlined (the scale).
    var solid = false
    @Environment(\.theme) private var theme
    var dimmed: (Degree) -> Bool = { _ in false }

    var body: some View {
        HStack(spacing: 4 * size) {
            ForEach(Array(degrees.enumerated()), id: \.offset) { _, degree in
                VStack(spacing: 0) {
                    Text(degree.intervalName)
                        .font(.system(size: 12 * size, weight: .bold))
                    Text(root.spelling(degree).description)
                        .font(.system(size: 10 * size))
                        .opacity(0.75)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Outlined: the text colour of wherever they are (light on the page, dark on the fretboard's cards)
                .foregroundStyle(solid ? AnyShapeStyle(theme.textColor(onInterval: degree.pitchClassOffset)) : AnyShapeStyle(.primary))
                .frame(width: 32 * size, height: 28 * size)
                .background(RoundedRectangle(cornerRadius: 5).fill(fill(degree)))
                // The root's chip is its colour (black), as on the fretboard, with an edge in the text colour so it
                // shows on a dark page
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(isRoot(degree) ? AnyShapeStyle(.primary.opacity(0.6)) : AnyShapeStyle(colour(degree)), lineWidth: 1.2))
                .opacity(dimmed(degree) ? 0.45 : 1)
            }
        }
    }

    private func isRoot(_ degree: Degree) -> Bool {
        ((degree.pitchClassOffset % 12) + 12) % 12 == 0
    }

    private func fill(_ degree: Degree) -> Color {
        if isRoot(degree) {
            return solid ? theme.intervalColor(0) : theme.intervalColor(0).opacity(0.35)
        }
        return colour(degree).opacity(solid ? 0.9 : 0.12)
    }
}

/// With the fretboard on its own (Fretboard Only), what to play: the chord now above the fretboard and
/// the next one below it, each with its scale and both sets of intervals, and when the change comes.
/// Both cards are the same height, so the fretboard sits in the middle.
struct FretboardReadout: View {
    enum Card { case now, next }

    let sequence: ChordSequence
    let editor: SequenceEditorState
    let card: Card

    /// Fits two rows of chips (the title, chord and scale sit beside them).
    static let height: CGFloat = 104

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(\.theme) private var theme

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { _ in
            let position = sequencePosition(editor, playback, transport)
            // A pinned chord holds, with nothing coming next
            let pinned = editor.pinnedRegion(in: sequence)
            let region = pinned ?? sequence.chord(at: max(position, 0))
            // (Round to the start of the loop at its end, while looping)
            let upcoming = pinned == nil ? sequence.upcomingChord(at: position) : nil
            let next = upcoming?.chord
            let beatInBar = Int(sequence.barAndBeat(at: position).beat)

            Group {
                if card == .now {
                    cardView(region, accent: .primary) {
                        title("NOW")
                        if let caption = pinned != nil ? "Pinned" : sequence.partName(at: max(position, 0)) {
                            Text(caption).font(.callout).opacity(0.6).lineLimit(1)
                        }
                        BeatDots(count: sequence.timeSignature.numerator, current: isPlaying ? beatInBar : nil)
                    }
                } else {
                    cardView(next, accent: nextChordColour) {
                        title("NEXT").foregroundColor(nextChordColour)
                        if let next {
                            let beatsLeft = Int(ceil(upcoming?.beatsAway ?? 0))
                            Text(beatsLeft == 1 ? "in 1 beat" : "in \(beatsLeft) beats")
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundColor(Double(beatsLeft) <= editor.leadUp(in: sequence) && isPlaying ? SpotStyle.warning : .secondary)
                            if let shift = shiftHint(from: region, to: next) {
                                Label(shift.text, systemImage: shift.up ? "arrow.up.right" : "arrow.down.left")
                                    .font(.callout)
                                    .foregroundColor(SpotStyle.warning)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(height: FretboardReadout.height)
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
    }

    /// A chord, its scale and both sets of intervals, under a title row.
    /// One row, to keep it short: the title, chord and scale on the left, their intervals to the right.
    private func cardView<Title: View>(_ region: ChordRegion?, accent: Color, @ViewBuilder title: () -> Title) -> some View {
        let chord = region.flatMap { editor.analysis.chords[$0.id] }
        let scale = region.flatMap { editor.analysis.scales[$0.id] }

        // The chord on the left, its intervals pushed to the right
        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    title()
                }
                Text(chord?.description ?? region?.symbol ?? "No chord")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(accent)
                    .opacity(chord == nil ? 0.3 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(chord.flatMap { chord in scale.map { "\(chord.root.description) \($0.name)" } } ?? " ")
                    .font(.title3)
                    .foregroundColor(accent.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 360, alignment: .leading)

            Spacer(minLength: 20)

            if let chord {
                let roles = scale.map { ChordScaleMatcher.roles(chord: chord.chord, scale: $0) } ?? [:]
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        rowLabel("CHORD")
                        IntervalChips(degrees: chord.chord.formula.degrees, root: chord.root, colour: { theme.chipColour($0) },
                                      size: 1.2, solid: true)
                    }
                    if let scale {
                        GridRow {
                            rowLabel("SCALE")
                            IntervalChips(degrees: scale.formula.degrees, root: chord.root, colour: { theme.chipColour($0) },
                                          size: 1.2, dimmed: { roles[$0.pitchClassOffset] == .avoid })
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .tracking(1.4)
            .opacity(0.7)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .opacity(0.5)
    }

    /// "Move up to fret 7" when the next chord's position is a stretch away from the current one.
    private func shiftHint(from current: ChordRegion?, to next: ChordRegion) -> (text: String, up: Bool)? {
        guard editor.neckView == .followHand, let current,
              let from = editor.analysis.positions[current.id], let to = editor.analysis.positions[next.id],
              abs(to.centre - from.centre) >= 2.5 else { return nil }
        let lowest = (to.voicing?.placement ?? to.placement).keys.map(\.fret).filter { $0 > 0 }.min() ?? Int(to.centre)
        return to.centre > from.centre ? ("Move up to fret \(lowest)", true) : ("Move down to fret \(lowest)", false)
    }
}


/// The beats of the bar, the first bigger and the one playing lit (smaller when there are many).
private struct BeatDots: View {
    let count: Int
    let current: Int?

    var body: some View {
        let size: CGFloat = count > 8 ? 6 : 10
        HStack(spacing: count > 8 ? 4 : 7) {
            ForEach(0..<max(count, 1), id: \.self) { beat in
                Circle()
                    .fill(beat == current ? Color.primary : Color.primary.opacity(0.18))
                    .frame(width: beat == 0 ? size + 3 : size, height: beat == 0 ? size + 3 : size)
            }
        }
    }
}

/// What the fretboard's markers mean, small, beside the chord's intervals.
private struct MarkerLegend: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Root", ring: .white, fill: theme.intervalColors[0], isRoot: true)
            row("Chord tone", ring: theme.intervalColors[4], fill: theme.intervalColors[4])
            row("Scale tone", ring: theme.intervalColors[2], fill: .black)
            row("Half: what it becomes next", ring: theme.intervalColors[7], fill: theme.intervalColors[7], split: theme.intervalColors[4])
            row("Dashed: new in next", ring: theme.intervalColors[11], fill: theme.intervalColors[11].opacity(0.3), dashed: true)
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.7))
        .fixedSize()
        .help("Each interval in its colour, as on the Library tab. Chord tones solid, the rest of the scale ringed with a black middle, the root a square. A note that carries into the next chord is half and half: what it is now, and what it becomes; a note the next chord brings in is dashed.")
    }

    private func row(_ title: String, ring: Color, fill: Color, isRoot: Bool = false, split: Color? = nil,
                     dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            let shape = MarkerShape(isRoot: isRoot)
            shape.stroke(ring, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [2, 1.5] : []))
                .background {
                    shape.fill(fill)
                    if let split {
                        shape.fill(split).mask(alignment: .trailing) { Rectangle().frame(width: 5) }
                    }
                }
                .frame(width: 10, height: 10)
                .frame(width: 14)
            Text(title)
        }
    }
}
