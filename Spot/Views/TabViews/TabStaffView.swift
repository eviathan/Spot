//
//  TabStaffView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Where everything goes on the page: bars wrapped into lines that fill the width, and each beat's position.
struct TabLayout {
    struct Beat {
        var index: Int
        var x: CGFloat
    }

    struct Bar {
        var index: Int
        var x: CGFloat
        var width: CGFloat
        var showsTimeSignature: Bool
        var beats: [Beat]
        /// Where the slot after the last beat is (for adding a beat).
        var appendX: CGFloat
    }

    struct Line {
        var bars: [Bar]
        var isFirst: Bool
    }

    var lines: [Line]

    static let leftMargin: CGFloat = 40
    static let timeSignatureWidth: CGFloat = 24
    static let repeatWidth: CGFloat = 12

    /// How much room a beat takes: longer notes more, but less than in proportion, so fast passages stay readable;
    /// more for techniques drawn beside the note (bends and their release curves most).
    static func space(for beat: TabBeat, zoom: Double) -> CGFloat {
        let quarters = Double(beat.duration.ticks) / Double(TabDuration.ticksPerQuarter)
        var extra: CGFloat = 0
        if let bend = beat.notes.compactMap(\.bend).first {
            extra += (bend.points.last?.cents ?? 0) < bend.peak ? 30 : 18
        }
        if beat.notes.contains(where: { $0.slide != nil || $0.legato }) { extra += 8 }
        if beat.notes.contains(where: \.vibrato) { extra += 8 }
        if beat.notes.contains(where: { $0.harmonic != nil || $0.isGhost || $0.isTied }) { extra += 6 }
        return max(28, CGFloat(32 * zoom * pow(quarters, 0.6))) + extra
    }

    static func make(score: TabScore, track: Int, width: CGFloat, zoom: Double) -> TabLayout {
        guard score.tracks.indices.contains(track) else { return TabLayout(lines: []) }
        let bars = score.tracks[track].bars
        let available = max(200, width - leftMargin - 16)

        // Each bar's natural width
        struct Natural { var index: Int; var header: CGFloat; var beats: [CGFloat]; var empty: Bool }
        var naturals: [Natural] = []
        for index in score.masterBars.indices {
            let master = score.masterBars[index]
            let changes = index == 0 || master.timeSignature != score.masterBars[index - 1].timeSignature
            var header: CGFloat = 10
            if changes { header += timeSignatureWidth }
            if master.isRepeatStart { header += repeatWidth }
            let beats = bars.indices.contains(index) ? bars[index].voices[0].beats : []
            naturals.append(Natural(index: index, header: header, beats: beats.map { space(for: $0, zoom: zoom) },
                                    empty: beats.isEmpty))
        }
        func naturalWidth(_ bar: Natural) -> CGFloat {
            // Room after the last beat for the cursor to add one, and for a repeat sign
            let end: CGFloat = 26 + (score.masterBars[bar.index].repeatCount > 0 ? repeatWidth : 0)
            return bar.header + (bar.empty ? CGFloat(90 * zoom) : bar.beats.reduce(0, +)) + end
        }

        // Fill lines, then stretch each (except the last) to the full width
        var lines: [Line] = []
        var current: [Natural] = []
        var used: CGFloat = 0
        func finish(stretch: Bool) {
            guard !current.isEmpty else { return }
            let natural = current.map(naturalWidth)
            let scale = stretch ? available / max(natural.reduce(0, +), 1) : 1
            var x = leftMargin
            var laidOut: [Bar] = []
            for (bar, width) in zip(current, natural) {
                let width = width * scale
                // The beats share whatever's left after the header and the end space
                let end: CGFloat = 26 + (score.masterBars[bar.index].repeatCount > 0 ? repeatWidth : 0)
                let room = width - bar.header - end
                let total = max(bar.beats.reduce(0, +), 1)
                var beatX = x + bar.header + 8
                var beats: [Beat] = []
                for (index, space) in bar.beats.enumerated() {
                    beats.append(Beat(index: index, x: beatX))
                    beatX += space / total * room
                }
                let appendX = bar.empty ? x + bar.header + 8 : beatX
                laidOut.append(Bar(index: bar.index, x: x, width: width,
                                   showsTimeSignature: bar.header >= 10 + timeSignatureWidth && (bar.index == 0 ||
                                       score.masterBars[bar.index].timeSignature != score.masterBars[bar.index - 1].timeSignature),
                                   beats: beats, appendX: appendX))
                x += width
            }
            lines.append(Line(bars: laidOut, isFirst: lines.isEmpty))
            current = []
            used = 0
        }
        for bar in naturals {
            let width = naturalWidth(bar)
            if !current.isEmpty && used + width > available {
                finish(stretch: true)
            }
            current.append(bar)
            used += width
        }
        finish(stretch: used > available * 0.75)
        return TabLayout(lines: lines)
    }
}

/// Sizes of the staff.
struct TabMetrics {
    var stringCount: Int
    let stringGap: CGFloat = 13
    /// Room above the staff, in rows (y from the top): markers and tempo (8), endings (24), chord names (48),
    /// tapping / accent / harmonic / strum marks and vibrato (62), let ring (74), palm mute (84), bends (90–96),
    /// bar numbers.
    let above: CGFloat = 104
    /// Room below: the rhythm.
    let below: CGFloat = 44

    var staffHeight: CGFloat { CGFloat(max(stringCount - 1, 1)) * stringGap }
    var lineHeight: CGFloat { above + staffHeight + below }

    /// The y of a string (0 the lowest, drawn at the bottom like tab).
    func y(string: Int) -> CGFloat {
        above + CGFloat(stringCount - 1 - string) * stringGap
    }

    func string(atY y: CGFloat) -> Int {
        let index = Int(((y - above) / stringGap).rounded())
        return min(max(stringCount - 1 - index, 0), stringCount - 1)
    }

    var rhythmTop: CGFloat { above + staffHeight + 8 }
}

/// The open tab's track as wrapped lines of tablature, with the cursor. Click a string at a beat to put the
/// cursor there.
struct TabStaffView: View {
    let score: TabScore
    let editor: TabEditorState
    @Environment(TabSession.self) private var session

    static let paper = Color(hue: 0.62, saturation: 0.38, brightness: 0.24)

    var body: some View {
        GeometryReader { geometry in
            let layout = TabLayout.make(score: score, track: editor.track, width: geometry.size.width, zoom: editor.zoom)
            let metrics = TabMetrics(stringCount: score.tracks.indices.contains(editor.track) ? score.tracks[editor.track].stringCount : 6)
            let playhead = session.playhead
            let playingLine = playhead.flatMap { playhead in layout.lines.firstIndex { $0.bars.contains { $0.index == playhead.bar } } }
            ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !score.title.isEmpty || !score.artist.isEmpty {
                        VStack(spacing: 2) {
                            if !score.title.isEmpty {
                                Text(score.title).font(.title2.weight(.semibold))
                            }
                            if !score.artist.isEmpty {
                                Text(score.artist).font(.callout).opacity(0.7)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }
                    ForEach(Array(layout.lines.enumerated()), id: \.offset) { index, line in
                        TabLineView(score: score, editor: editor, line: line, metrics: metrics, width: geometry.size.width,
                                    playhead: index == playingLine ? playhead : nil)
                            .id(index)
                    }
                }
                .padding(.bottom, 24)
            }
            // Keep the line being played in view
            .onChange(of: playingLine) { _, line in
                guard let line else { return }
                withAnimation(.easeInOut(duration: 0.3)) { scroller.scrollTo(line, anchor: .center) }
            }
            }
        }
        .background(TabStaffView.paper)
    }
}

/// One line of bars.
private struct TabLineView: View {
    let score: TabScore
    let editor: TabEditorState
    let line: TabLayout.Line
    let metrics: TabMetrics
    let width: CGFloat
    /// The beat being played, if it's on this line.
    var playhead: TabPosition?

    private var track: TabTrack? {
        score.tracks.indices.contains(editor.track) ? score.tracks[editor.track] : nil
    }

    var body: some View {
        let cursor = editor.cursor
        let selection = editor.selection
        Canvas { context, size in
            guard let track else { return }
            draw(track: track, cursor: cursor, selection: selection, in: &context, size: size)
        }
        .frame(width: width, height: metrics.lineHeight)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in place(at: tap.location) })
    }

    /// Puts the cursor on the beat (or the slot after the last one) and string nearest a click.
    private func place(at point: CGPoint) {
        guard let bar = line.bars.first(where: { point.x >= $0.x && point.x < $0.x + $0.width }) ?? line.bars.last else { return }
        let slots = bar.beats.map { ($0.index, $0.x) } + [(bar.beats.count, bar.appendX)]
        let nearest = slots.min { abs($0.1 - point.x) < abs($1.1 - point.x) }!
        editor.cursor = TabEditorState.Cursor(bar: bar.index, beat: nearest.0, string: metrics.string(atY: point.y))
    }

    // MARK: - Drawing

    private func draw(track: TabTrack, cursor: TabEditorState.Cursor, selection: (start: TabPosition, end: TabPosition)?,
                      in context: inout GraphicsContext, size: CGSize) {
        let ink = Color.white
        let lineColour = Color.white.opacity(0.35)
        let top = metrics.y(string: track.stringCount - 1), bottom = metrics.y(string: 0)
        let lastX = line.bars.last.map { $0.x + $0.width } ?? TabLayout.leftMargin

        // Strings
        var strings = Path()
        for string in 0..<track.stringCount {
            strings.move(to: CGPoint(x: TabLayout.leftMargin, y: metrics.y(string: string)))
            strings.addLine(to: CGPoint(x: lastX, y: metrics.y(string: string)))
        }
        context.stroke(strings, with: .color(lineColour), lineWidth: 1)

        // TAB down the left
        for (index, letter) in ["T", "A", "B"].enumerated() {
            let y = (top + bottom) / 2 + CGFloat(index - 1) * 12
            context.draw(Text(letter).font(.system(size: 12, weight: .heavy)).foregroundColor(ink.opacity(0.8)),
                         at: CGPoint(x: 24, y: y))
        }
        // The start of the line
        context.stroke(Path { $0.move(to: CGPoint(x: TabLayout.leftMargin, y: top)); $0.addLine(to: CGPoint(x: TabLayout.leftMargin, y: bottom)) },
                       with: .color(lineColour), lineWidth: 1)

        for bar in line.bars {
            drawBar(bar, track: track, cursor: cursor, selection: selection, top: top, bottom: bottom, in: &context)
        }
        drawTechniques(track: track, top: top, lineEnd: lastX, in: &context)
    }

    // MARK: - Techniques

    /// Arcs, slides and bends between and on notes; marks for vibrato, tapping, accents, harmonics and strums;
    /// "let ring" and "P.M." over runs of beats.
    private func drawTechniques(track: TabTrack, top: CGFloat, lineEnd: CGFloat, in context: inout GraphicsContext) {
        let ink = Color.white.opacity(0.85)
        // Every beat on the line, in order
        var slots: [(x: CGFloat, beat: TabBeat)] = []
        for bar in line.bars where track.bars.indices.contains(bar.index) {
            let beats = track.bars[bar.index].voices[0].beats
            for slot in bar.beats where beats.indices.contains(slot.index) {
                slots.append((slot.x, beats[slot.index]))
            }
        }
        /// The next note on a string after a beat, on this line (x and fret), or the end of the line.
        func next(after index: Int, string: Int) -> (x: CGFloat, fret: Int?) {
            for later in slots[(index + 1)...] {
                if let note = later.beat.notes.first(where: { $0.string == string }) {
                    return (later.x, note.fret)
                }
            }
            return (lineEnd - 4, nil)
        }

        for (index, slot) in slots.enumerated() {
            let x = slot.x
            for note in slot.beat.notes where note.string < track.stringCount {
                let y = metrics.y(string: note.string)
                let target = next(after: index, string: note.string)

                // Hammer-on / pull-off: an arc to the next note, H going up, P coming down
                if note.legato {
                    var arc = Path()
                    arc.move(to: CGPoint(x: x + 5, y: y - 7))
                    arc.addQuadCurve(to: CGPoint(x: target.x - 5, y: y - 7), control: CGPoint(x: (x + target.x) / 2, y: y - 16))
                    context.stroke(arc, with: .color(ink), lineWidth: 1)
                    if let fret = target.fret {
                        context.draw(Text(fret >= note.fret ? "H" : "P").font(.system(size: 8, weight: .bold)).foregroundColor(ink),
                                     at: CGPoint(x: (x + target.x) / 2, y: y - 17))
                    }
                }

                // Slides
                if let slide = note.slide {
                    var line = Path()
                    switch slide {
                    case .shift, .legato:
                        let rising = (target.fret ?? note.fret) >= note.fret
                        line.move(to: CGPoint(x: x + 8, y: y + (rising ? 3 : -3)))
                        line.addLine(to: CGPoint(x: target.x - 8, y: y + (rising ? -3 : 3)))
                        if slide == .legato {
                            var arc = Path()
                            arc.move(to: CGPoint(x: x + 5, y: y - 7))
                            arc.addQuadCurve(to: CGPoint(x: target.x - 5, y: y - 7), control: CGPoint(x: (x + target.x) / 2, y: y - 16))
                            context.stroke(arc, with: .color(ink), lineWidth: 1)
                        }
                    case .outDownwards:
                        line.move(to: CGPoint(x: x + 8, y: y - 3)); line.addLine(to: CGPoint(x: x + 20, y: y + 4))
                    case .outUpwards:
                        line.move(to: CGPoint(x: x + 8, y: y + 3)); line.addLine(to: CGPoint(x: x + 20, y: y - 4))
                    case .inFromBelow:
                        line.move(to: CGPoint(x: x - 20, y: y + 4)); line.addLine(to: CGPoint(x: x - 8, y: y - 3))
                    case .inFromAbove:
                        line.move(to: CGPoint(x: x - 20, y: y - 4)); line.addLine(to: CGPoint(x: x - 8, y: y + 3))
                    }
                    context.stroke(line, with: .color(ink), lineWidth: 1.2)
                }

                // Bends: an arrow up above the staff with the amount, and a dashed curve back down for a release
                if let bend = note.bend, bend.peak > 0 {
                    let tip = CGPoint(x: x + 16, y: 98)
                    let startsBent = (bend.points.first?.cents ?? 0) > 0
                    let releases = (bend.points.last?.cents ?? 0) < bend.peak
                    var up = Path()
                    if startsBent {
                        up.move(to: CGPoint(x: x + 6, y: y - 6))
                        up.addLine(to: CGPoint(x: x + 6, y: 98))
                    } else {
                        up.move(to: CGPoint(x: x + 7, y: y))
                        up.addQuadCurve(to: tip, control: CGPoint(x: x + 16, y: y))
                    }
                    context.stroke(up, with: .color(ink), lineWidth: 1.2)
                    let head = startsBent ? CGPoint(x: x + 6, y: 98) : tip
                    var arrow = Path()
                    arrow.move(to: CGPoint(x: head.x - 3, y: head.y + 5))
                    arrow.addLine(to: head)
                    arrow.addLine(to: CGPoint(x: head.x + 3, y: head.y + 5))
                    context.stroke(arrow, with: .color(ink), lineWidth: 1.2)
                    context.draw(Text(bendLabel(bend.peak)).font(.system(size: 9, weight: .semibold)).foregroundColor(ink),
                                 at: CGPoint(x: head.x, y: 91))
                    if releases {
                        var down = Path()
                        down.move(to: head)
                        down.addQuadCurve(to: CGPoint(x: head.x + 14, y: y - 4), control: CGPoint(x: head.x + 14, y: head.y))
                        context.stroke(down, with: .color(ink), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                    }
                }
            }

            // Marks above the beat
            let notes = slot.beat.notes
            var marks: [String] = []
            if let stroke = slot.beat.stroke { marks.append(stroke == .down ? "⊓" : "V") }
            if notes.contains(where: \.tapped) { marks.append("T") }
            if notes.contains(where: \.accent) { marks.append(">") }
            if let harmonic = notes.compactMap(\.harmonic).first(where: { $0 != .natural }) {
                marks.append(["artificial": "A.H.", "pinch": "P.H.", "tapped": "T.H.", "semi": "S.H."][harmonic.rawValue] ?? "")
            }
            if notes.contains(where: \.vibrato) {
                var wave = Path()
                let start = x - 8
                wave.move(to: CGPoint(x: start, y: 62))
                for step in 0..<6 {
                    let x0 = start + CGFloat(step) * 4
                    wave.addQuadCurve(to: CGPoint(x: x0 + 4, y: 62), control: CGPoint(x: x0 + 2, y: step % 2 == 0 ? 58 : 66))
                }
                context.stroke(wave, with: .color(ink), lineWidth: 1.2)
            }
            if !marks.isEmpty {
                context.draw(Text(marks.joined(separator: " ")).font(.system(size: 10, weight: .bold)).foregroundColor(ink),
                             at: CGPoint(x: notes.contains(where: \.vibrato) ? x + 24 : x, y: 62))
            }
        }

        // "let ring" and "P.M." with a dashed line over each run of beats that has them
        drawRuns(slots: slots.map { ($0.x, $0.beat.notes.contains(where: \.letRing)) }, label: "let ring", y: 74, in: &context)
        drawRuns(slots: slots.map { ($0.x, $0.beat.notes.contains(where: \.palmMute)) }, label: "P.M.", y: 84, in: &context)
    }

    private func drawRuns(slots: [(x: CGFloat, on: Bool)], label: String, y: CGFloat, in context: inout GraphicsContext) {
        let ink = Color.white.opacity(0.85)
        var index = 0
        while index < slots.count {
            guard slots[index].on else { index += 1; continue }
            var last = index
            while last + 1 < slots.count, slots[last + 1].on { last += 1 }
            let start = slots[index].x - 10
            let text = context.resolve(Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(ink))
            let width = text.measure(in: CGSize(width: 100, height: 20)).width
            context.draw(text, at: CGPoint(x: start, y: y), anchor: .leading)
            let end = slots[last].x + 10
            if end > start + width + 6 {
                var dashes = Path()
                dashes.move(to: CGPoint(x: start + width + 4, y: y))
                dashes.addLine(to: CGPoint(x: end, y: y))
                dashes.move(to: CGPoint(x: end, y: y - 3))
                dashes.addLine(to: CGPoint(x: end, y: y + 3))
                context.stroke(dashes, with: .color(ink), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            index = last + 1
        }
    }

    /// e.g. "full" for 200 cents, "½" for 100, "1½" for 300.
    private func bendLabel(_ cents: Int) -> String {
        let quarters = Int((Double(cents) / 50).rounded())   // quarter tones
        let whole = quarters / 4
        let fraction = ["", "¼", "½", "¾"][quarters % 4]
        if quarters == 4 { return "full" }
        return whole == 0 ? fraction : "\(whole)\(fraction)"
    }

    private func drawBar(_ bar: TabLayout.Bar, track: TabTrack, cursor: TabEditorState.Cursor,
                         selection: (start: TabPosition, end: TabPosition)?,
                         top: CGFloat, bottom: CGFloat, in context: inout GraphicsContext) {
        let ink = Color.white
        let master = score.masterBars[bar.index]
        let end = bar.x + bar.width
        var headerX = bar.x + 6


        // Bar number (red when the beats don't add up to the bar) and anything above the bar
        let fill = score.fill(track: editor.track, bar: bar.index)
        context.draw(Text("\(bar.index + 1)").font(.system(size: 9, weight: fill == 0 ? .regular : .bold))
                        .foregroundColor(fill == 0 ? ink.opacity(0.45) : Color(red: 1, green: 0.4, blue: 0.4)),
                     at: CGPoint(x: bar.x + 3, y: top - 10), anchor: .leading)
        var aboveY: CGFloat = 8
        if let marker = master.marker, !marker.isEmpty {
            let text = context.resolve(Text(marker).font(.system(size: 11, weight: .bold)).foregroundColor(.black))
            let size = text.measure(in: CGSize(width: 300, height: 30))
            context.fill(Path(roundedRect: CGRect(x: bar.x + 2, y: aboveY - 1, width: size.width + 8, height: size.height + 2), cornerRadius: 3),
                         with: .color(Color(red: 0.95, green: 0.78, blue: 0.35)))
            context.draw(text, at: CGPoint(x: bar.x + 6, y: aboveY), anchor: .topLeading)
            aboveY += 0
        }
        let tempo = master.tempo ?? (bar.index == 0 ? score.tempo : nil)
        if let tempo {
            let x = bar.x + (master.marker?.isEmpty == false ? 90 : 4)
            context.draw(Text("♩ = \(Int(tempo.rounded()))").font(.system(size: 11)).foregroundColor(ink.opacity(0.85)),
                         at: CGPoint(x: x, y: aboveY), anchor: .topLeading)
        }
        if !master.alternateEndings.isEmpty {
            var bracket = Path()
            let y: CGFloat = 26
            bracket.move(to: CGPoint(x: bar.x + 2, y: y + 8))
            bracket.addLine(to: CGPoint(x: bar.x + 2, y: y))
            bracket.addLine(to: CGPoint(x: end - 4, y: y))
            context.stroke(bracket, with: .color(ink.opacity(0.7)), lineWidth: 1)
            context.draw(Text(master.alternateEndings.map { "\($0)." }.joined(separator: " ")).font(.system(size: 10, weight: .semibold))
                            .foregroundColor(ink.opacity(0.8)),
                         at: CGPoint(x: bar.x + 6, y: y + 1), anchor: .topLeading)
        }

        // Repeat start: thick, thin, dots
        if master.isRepeatStart {
            context.fill(Path(CGRect(x: headerX - 2, y: top, width: 3, height: bottom - top)), with: .color(ink.opacity(0.85)))
            context.stroke(Path { $0.move(to: CGPoint(x: headerX + 3, y: top)); $0.addLine(to: CGPoint(x: headerX + 3, y: bottom)) },
                           with: .color(ink.opacity(0.85)), lineWidth: 1)
            for y in repeatDotYs(top: top, bottom: bottom) {
                context.fill(Path(ellipseIn: CGRect(x: headerX + 5, y: y - 1.5, width: 3, height: 3)), with: .color(ink))
            }
            headerX += TabLayout.repeatWidth
        }

        // Time signature, big, across the staff
        if bar.showsTimeSignature {
            let size = min(22, (bottom - top) / 2 + 4)
            let middle = (top + bottom) / 2
            context.draw(Text("\(master.timeSignature.numerator)").font(.system(size: size, weight: .heavy)).foregroundColor(ink),
                         at: CGPoint(x: headerX + 9, y: middle - size * 0.45))
            context.draw(Text("\(master.timeSignature.denominator)").font(.system(size: size, weight: .heavy)).foregroundColor(ink),
                         at: CGPoint(x: headerX + 9, y: middle + size * 0.45))
        }

        // Bar line, or a repeat end: dots, thin, thick, and how many times
        if master.repeatCount > 0 {
            for y in repeatDotYs(top: top, bottom: bottom) {
                context.fill(Path(ellipseIn: CGRect(x: end - 10, y: y - 1.5, width: 3, height: 3)), with: .color(ink))
            }
            context.stroke(Path { $0.move(to: CGPoint(x: end - 5, y: top)); $0.addLine(to: CGPoint(x: end - 5, y: bottom)) },
                           with: .color(ink.opacity(0.85)), lineWidth: 1)
            context.fill(Path(CGRect(x: end - 2, y: top, width: 3, height: bottom - top)), with: .color(ink.opacity(0.85)))
            if master.repeatCount > 2 {
                context.draw(Text("×\(master.repeatCount)").font(.system(size: 10, weight: .semibold)).foregroundColor(ink.opacity(0.85)),
                             at: CGPoint(x: end - 4, y: top - 10), anchor: .trailing)
            }
        } else {
            context.stroke(Path { $0.move(to: CGPoint(x: end, y: top)); $0.addLine(to: CGPoint(x: end, y: bottom)) },
                           with: .color(Color.white.opacity(0.5)), lineWidth: 1)
        }

        // Notes, chord names, rests
        let beats = track.bars.indices.contains(bar.index) ? track.bars[bar.index].voices[0].beats : []
        for slot in bar.beats {
            let beat = beats[slot.index]
            if let chord = beat.chord, !chord.isEmpty {
                context.draw(Text(chord).font(.system(size: 12, weight: .semibold)).foregroundColor(ink),
                             at: CGPoint(x: slot.x, y: 48))
            }
            if beat.isRest {
                drawRest(beat.duration.value, at: CGPoint(x: slot.x, y: (top + bottom) / 2), in: &context)
            }
            for note in beat.notes where note.string < track.stringCount {
                drawNote(note, at: CGPoint(x: slot.x, y: metrics.y(string: note.string)), in: &context)
            }
        }
        drawRhythm(bar: bar, beats: beats, timeSignature: master.timeSignature, in: &context)

        // Selected beats and the cursor's column, as a tint over the notes (under them, the patches that clear
        // the strings behind each fret number would show as dark boxes)
        if let selection {
            for slot in bar.beats {
                let position = TabPosition(bar: bar.index, beat: slot.index)
                if position >= selection.start && position <= selection.end {
                    context.fill(Path(roundedRect: CGRect(x: slot.x - 11, y: top - 8, width: 22, height: bottom - top + 16), cornerRadius: 4),
                                 with: .color(Color.accentColor.opacity(0.25)))
                }
            }
        }
        if cursor.bar == bar.index {
            let x = cursor.beat < bar.beats.count ? bar.beats[cursor.beat].x : bar.appendX
            context.fill(Path(roundedRect: CGRect(x: x - 11, y: top - 8, width: 22, height: bottom - top + 16), cornerRadius: 4),
                         with: .color(Color.white.opacity(0.07)))
        }
        // The beat being played
        if let playhead, playhead.bar == bar.index, bar.beats.indices.contains(playhead.beat) {
            let x = bar.beats[playhead.beat].x
            context.fill(Path(roundedRect: CGRect(x: x - 11, y: top - 8, width: 22, height: bottom - top + 16), cornerRadius: 4),
                         with: .color(Color(red: 0.55, green: 0.85, blue: 0.45).opacity(0.3)))
            context.fill(Path(CGRect(x: x - 11, y: top - 14, width: 22, height: 3)),
                         with: .color(Color(red: 0.55, green: 0.85, blue: 0.45)))
        }

        // The cursor itself: a box round the string at the beat
        if cursor.bar == bar.index {
            let x = cursor.beat < bar.beats.count ? bar.beats[cursor.beat].x : bar.appendX
            let y = metrics.y(string: min(cursor.string, track.stringCount - 1))
            context.stroke(Path(roundedRect: CGRect(x: x - 10, y: y - 8, width: 20, height: 16), cornerRadius: 3),
                           with: .color(.orange), lineWidth: 1.5)
        }
    }

    private func repeatDotYs(top: CGFloat, bottom: CGFloat) -> [CGFloat] {
        let middle = (top + bottom) / 2
        return [middle - metrics.stringGap / 2 - 2, middle + metrics.stringGap / 2 + 2]
    }

    /// A fret number with the string broken behind it; dead notes as x, tied and ghost notes in brackets,
    /// harmonics in angle brackets.
    private func drawNote(_ note: TabNote, at point: CGPoint, in context: inout GraphicsContext) {
        var label = note.isDead ? "x" : "\(note.fret)"
        if note.harmonic != nil { label = "⟨\(label)⟩" }
        if note.isTied || note.isGhost { label = "(\(label))" }
        let text = context.resolve(Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.white))
        let size = text.measure(in: CGSize(width: 80, height: 20))
        context.fill(Path(CGRect(x: point.x - size.width / 2 - 1.5, y: point.y - size.height / 2, width: size.width + 3, height: size.height)),
                     with: .color(TabStaffView.paper))
        context.draw(text, at: point)
    }

    /// Rests drawn as shapes (no music font to rely on): a block hanging from or sitting on the middle for
    /// whole and half, the zigzag for a quarter, a stem with one flag per beam for shorter ones.
    private func drawRest(_ value: TabDuration.Value, at centre: CGPoint, in context: inout GraphicsContext) {
        let ink = Color.white.opacity(0.85)
        let x = centre.x, y = centre.y
        // Clear the strings behind it
        context.fill(Path(CGRect(x: x - 7, y: y - 12, width: 14, height: 24)), with: .color(TabStaffView.paper))
        switch value {
        case .whole:
            context.stroke(Path { $0.move(to: CGPoint(x: x - 7, y: y - 5)); $0.addLine(to: CGPoint(x: x + 7, y: y - 5)) },
                           with: .color(ink), lineWidth: 1)
            context.fill(Path(CGRect(x: x - 5, y: y - 5, width: 10, height: 4)), with: .color(ink))
        case .half:
            context.stroke(Path { $0.move(to: CGPoint(x: x - 7, y: y + 1)); $0.addLine(to: CGPoint(x: x + 7, y: y + 1)) },
                           with: .color(ink), lineWidth: 1)
            context.fill(Path(CGRect(x: x - 5, y: y - 3, width: 10, height: 4)), with: .color(ink))
        case .quarter:
            var zigzag = Path()
            zigzag.move(to: CGPoint(x: x - 2, y: y - 10))
            zigzag.addLine(to: CGPoint(x: x + 3, y: y - 4))
            zigzag.addLine(to: CGPoint(x: x - 2, y: y + 1))
            zigzag.addLine(to: CGPoint(x: x + 3, y: y + 6))
            zigzag.addQuadCurve(to: CGPoint(x: x, y: y + 11), control: CGPoint(x: x - 5, y: y + 5))
            context.stroke(zigzag, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        default:
            let flags = [TabDuration.Value.eighth: 1, .sixteenth: 2, .thirtySecond: 3, .sixtyFourth: 4][value] ?? 1
            context.stroke(Path { $0.move(to: CGPoint(x: x + 3, y: y - 8)); $0.addLine(to: CGPoint(x: x - 1, y: y + 9)) },
                           with: .color(ink), lineWidth: 1.5)
            for flag in 0..<flags {
                let flagY = y - 8 + CGFloat(flag) * 5
                let stemX = x + 3 - CGFloat(flag) * 5 * 4 / 17
                context.fill(Path(ellipseIn: CGRect(x: stemX - 6, y: flagY - 1, width: 3.5, height: 3.5)), with: .color(ink))
                context.stroke(Path { $0.move(to: CGPoint(x: stemX - 4.5, y: flagY + 1)); $0.addLine(to: CGPoint(x: stemX, y: flagY)) },
                               with: .color(ink), lineWidth: 1.2)
            }
        }
    }

    // MARK: - Rhythm under the staff

    /// Stems under each beat, beamed in groups of a beat (a dotted quarter in compound time), with dots and
    /// tuplet numbers.
    private func drawRhythm(bar: TabLayout.Bar, beats: [TabBeat], timeSignature: TimeSignature, in context: inout GraphicsContext) {
        guard !beats.isEmpty else { return }
        let ink = Color.white.opacity(0.85)
        let stemTop = metrics.rhythmTop, stemBottom = metrics.rhythmTop + 22
        let compound = timeSignature.denominator == 8 && timeSignature.numerator % 3 == 0
        let groupTicks = compound ? TabDuration.ticksPerQuarter * 3 / 2 : TabDuration.ticksPerQuarter * 4 / timeSignature.denominator

        // Which beam group each beat starts in
        var start = 0
        var groups: [Int] = []
        for beat in beats {
            groups.append(start / max(groupTicks, 1))
            start += beat.duration.ticks
        }
        func beamCount(_ beat: TabBeat) -> Int {
            switch beat.duration.value {
            case .eighth: return 1
            case .sixteenth: return 2
            case .thirtySecond: return 3
            case .sixtyFourth: return 4
            default: return 0
            }
        }

        for (index, beat) in beats.enumerated() where !beat.isRest {
            let x = bar.beats[index].x
            switch beat.duration.value {
            case .whole:
                break
            case .half:
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: stemTop + 10)); $0.addLine(to: CGPoint(x: x, y: stemBottom)) },
                               with: .color(ink), lineWidth: 1)
            default:
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: stemTop)); $0.addLine(to: CGPoint(x: x, y: stemBottom)) },
                               with: .color(ink), lineWidth: 1)
            }
            for dot in 0..<beat.duration.dots {
                context.fill(Path(ellipseIn: CGRect(x: x + 4 + CGFloat(dot) * 4, y: stemBottom - 2, width: 2.5, height: 2.5)), with: .color(ink))
            }

            // Beams to the next beat in the same group; a flag if there's no neighbour to beam to
            let beams = beamCount(beat)
            guard beams > 0 else { continue }
            let next = index + 1 < beats.count && !beats[index + 1].isRest && groups[index + 1] == groups[index]
                && beamCount(beats[index + 1]) > 0 ? index + 1 : nil
            let previous = index > 0 && !beats[index - 1].isRest && groups[index - 1] == groups[index]
                && beamCount(beats[index - 1]) > 0 ? index - 1 : nil
            if let next {
                let shared = min(beams, beamCount(beats[next]))
                for level in 0..<shared {
                    let y = stemBottom - CGFloat(level) * 4
                    context.fill(Path(CGRect(x: x, y: y - 1.5, width: bar.beats[next].x - x, height: 2.5)), with: .color(ink))
                }
                // Extra beams this beat has that the next doesn't: a short stub
                for level in shared..<beams where previous == nil {
                    let y = stemBottom - CGFloat(level) * 4
                    context.fill(Path(CGRect(x: x, y: y - 1.5, width: 6, height: 2.5)), with: .color(ink))
                }
            } else if previous == nil {
                for level in 0..<beams {
                    let y = stemBottom - CGFloat(level) * 4
                    var flag = Path()
                    flag.move(to: CGPoint(x: x, y: y))
                    flag.addLine(to: CGPoint(x: x + 6, y: y - 5))
                    context.stroke(flag, with: .color(ink), lineWidth: 1.5)
                }
            } else {
                // Last in a beamed group, with more beams than the one before: a stub back
                let shared = min(beams, beamCount(beats[previous!]))
                for level in shared..<beams {
                    let y = stemBottom - CGFloat(level) * 4
                    context.fill(Path(CGRect(x: x - 6, y: y - 1.5, width: 6, height: 2.5)), with: .color(ink))
                }
            }
        }

        // Tuplet numbers under each run of beats in the same tuplet
        var index = 0
        while index < beats.count {
            guard let tuplet = beats[index].duration.tuplet else { index += 1; continue }
            var last = index
            while last + 1 < beats.count, beats[last + 1].duration.tuplet == tuplet, last + 1 - index < tuplet.notes { last += 1 }
            let middle = (bar.beats[index].x + bar.beats[last].x) / 2
            context.draw(Text("\(tuplet.notes)").font(.system(size: 9, weight: .semibold)).foregroundColor(ink),
                         at: CGPoint(x: middle, y: stemBottom + 9))
            index = last + 1
        }
    }
}
