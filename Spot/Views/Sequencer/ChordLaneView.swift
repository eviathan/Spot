//
//  ChordLaneView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Sections, chords, bars and the recording on a timeline. While stopped it scrolls freely and clicks
/// select; while playing the lane moves past a playhead fixed a quarter of the way across.
/// Only the visible part of the waveform is drawn, so long songs stay quick.
struct ChordLaneView: View {
    /// Every how many bars to draw something (1, 2, 4, 8…) so that they're at least `minimumSpacing` apart.
    static func barStep(barPixels: CGFloat, minimumSpacing: CGFloat) -> Int {
        var step = 1
        while barPixels * CGFloat(step) < minimumSpacing && step < 4096 {
            step *= 2
        }
        return step
    }

    let sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(SequenceSession.self) private var session

    /// The height the lane has to fill.
    @State private var availableHeight: CGFloat = 0
    /// What's drawn while a mouse button is down (see `drawnRange`).
    @State private var pressedRange = PressedRange()
    /// The loop brace as it's being dragged.
    @State private var loopDrag: BeatRange?
    /// The start or end marker as it's being dragged, so the grid follows it.
    @State private var markerDrag: (marker: SongMarker, beat: Double)?
    /// Where the pointer is over the lane, for the right-click menu. Kept in a plain object so moving
    /// the mouse doesn't redraw the lane (which made zooming and dragging stall).
    @State private var pointer = PointerPosition()

    private final class PointerPosition {
        var beat: Double = 0
    }

    private enum SongMarker { case start, end }
    static let contentSpace = "lane-content"
    private let markerColour = Color(red: 0.36, green: 0.82, blue: 0.62)

    /// 1.1.1 and the end, following a drag in progress.
    private var origin: Double {
        markerDrag?.marker == .start ? markerDrag!.beat : sequence.startBeat
    }
    private var songEnd: Double {
        markerDrag?.marker == .end ? markerDrag!.beat : sequence.songEnd
    }

    /// Sections and chords, the recording's row (empty until there is one), and a row of takes when there are any.
    private var laneHeight: CGFloat {
        takesTop + (sequence.takes.isEmpty ? 0 : takesHeight + 4) + 20
    }
    let waveformTop: CGFloat = 84
    let takesHeight: CGFloat = 22
    /// The waveform takes whatever room the rest of the lane leaves.
    private var waveformHeight: CGFloat {
        max(84, availableHeight - waveformTop - 4 - (sequence.takes.isEmpty ? 0 : takesHeight + 4) - 20)
    }
    private var takesTop: CGFloat {
        waveformTop + waveformHeight + 4
    }

    private var beatWidth: CGFloat {
        editor.barWidth / CGFloat(sequence.barLength)
    }

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                rowHeaders
                // The view stays put while playing; the playhead moves across it (and turns the page, if following)
                GeometryReader { geometry in
                    let viewport = geometry.size.width
                    let left = CGFloat(editor.viewStart) * beatWidth
                    lane(visible: drawnRange(left...(left + viewport)))
                        .overlay(alignment: .topLeading) {
                            if isPlaying {
                                PlayingPlayhead(editor: editor, beatWidth: beatWidth, height: laneHeight)
                            } else {
                                StoppedPlayhead(editor: editor, beatWidth: beatWidth, height: laneHeight)
                            }
                        }
                        .offset(x: -left)
                        .frame(width: viewport, alignment: .leading)
                        .clipped()
                        .contentShape(Rectangle())
                }
                // Stopping (or reaching the end) brings the playhead back into view, if following
            .onChange(of: isPlaying) { _, playing in
                if !playing {
                    editor.revealPlayhead()
                }
            }
            .frame(minHeight: waveformTop + 84 + (sequence.takes.isEmpty ? 0 : takesHeight + 4) + 20, maxHeight: .infinity)
                // Trackpad: swipe to pan, pinch (or ⌘/⌥ + scroll) to zoom around the pointer
                .background(ScrollCatcher(
                    onScroll: { event, x in
                        var dx = event.scrollingDeltaX
                        var dy = event.scrollingDeltaY
                        if !event.hasPreciseScrollingDeltas {
                            dx *= 8
                            dy *= 8
                        }
                        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                            editor.zoom(by: exp(Double(dy) * 0.01), around: Double(x))
                        } else {
                            editor.pan(by: -Double(abs(dx) >= abs(dy) ? dx : dy))
                            if isPlaying { editor.viewMovedByHand() }
                        }
                    },
                    onMagnify: { magnification, x in
                        editor.zoom(by: 1 + Double(magnification), around: Double(x))
                    }))
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            updateViewport(geometry.size.width)
                            availableHeight = geometry.size.height
                        }
                        .onChange(of: geometry.size.width) { _, width in updateViewport(width) }
                        .onChange(of: geometry.size.height) { _, height in availableHeight = height }
                        .onChange(of: sequence.lengthInBeats) { updateViewport(geometry.size.width) }
                        .onChange(of: sequence.timeSignature) { updateViewport(geometry.size.width) }
                })

            }

            HStack(spacing: 0) {
                Color.clear.frame(width: laneHeaderWidth, height: 1)
                LaneOverview(editor: editor, lengthInBeats: sequence.lengthInBeats, isPlaying: isPlaying)
            }
            .padding(.vertical, 5)
        }
    }

    /// The part of the lane to draw: what's on screen, except while a mouse button is down. Then nothing drawn
    /// since the press goes, even if a scroll or zoom (a trackpad, while the button's held) takes it off screen:
    /// a view removed while it's being pressed never hears the mouse come up, and SwiftUI then ignores every
    /// click in the window.
    private func drawnRange(_ onScreen: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        let beats = Double(onScreen.lowerBound / beatWidth)...Double(onScreen.upperBound / beatWidth)
        if !MouseButtons.isDown {
            pressedRange.beats = beats
            return onScreen
        }
        let held = pressedRange.beats.map { min($0.lowerBound, beats.lowerBound)...max($0.upperBound, beats.upperBound) } ?? beats
        pressedRange.beats = held
        return CGFloat(held.lowerBound) * beatWidth...CGFloat(held.upperBound) * beatWidth
    }

    /// What each row of the lane is, lined up with it: sections and chords, the recording (with its
    /// controls), and takes.
    private var rowHeaders: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                rowTitle("Patterns", systemImage: "repeat")
                    .frame(height: 30, alignment: .center)
                rowTitle("Chords", systemImage: "music.quarternote.3")
                    .frame(height: 46, alignment: .center)
            }
            .frame(height: waveformTop, alignment: .top)
            Divider()
            AudioTrackHeader(sequence: sequence, editor: editor, height: waveformHeight + 3)
            if !sequence.takes.isEmpty {
                Divider()
                rowTitle("Takes", systemImage: "mic")
                    .frame(height: takesHeight + 3, alignment: .center)
            }
            Spacer(minLength: 0)
        }
        .frame(width: laneHeaderWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.14))
        .overlay(alignment: .trailing) { Divider() }
    }

    private func rowTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .opacity(0.75)
            .padding(.horizontal, 10)
    }

    private func updateViewport(_ width: CGFloat) {
        editor.setViewport(width: Double(width), lengthInBeats: sequence.lengthInBeats, timeSignature: sequence.timeSignature)
    }

    private func lane(visible: ClosedRange<CGFloat>) -> some View {
        let width = CGFloat(sequence.lengthInBeats) * beatWidth
        let isPlaying = playback.playingSequence == editor.id

        return ZStack(alignment: .topLeading) {
            // Selection (shown while playing too, like Live) and loop
            SelectionHighlight(editor: editor, beatWidth: beatWidth, height: laneHeight, visible: visible)

            // Patterns: their tint and repeat lines under the chords (their bars go on top, below)
            PatternLayer(sequence: sequence, editor: editor, beatWidth: beatWidth, visible: visible, isEditable: !isPlaying,
                         showsBars: false)

            // Chords, which can be moved and resized; clicking or dragging between them selects
            // (Not rebuilt when only something else changes, e.g. a warp marker: the clips are the costliest part)
            ChordClipsLayer(sequence: sequence, editor: editor, beatWidth: beatWidth,
                            height: waveformTop, isEditable: !isPlaying, visible: visible)
                .equatable()

            // The patterns' bars, over the chord row's click-catching background so they can be dragged and clicked
            PatternLayer(sequence: sequence, editor: editor, beatWidth: beatWidth, visible: visible, isEditable: !isPlaying,
                         showsBars: true)

            // Bar lines and numbers (only those on screen), counted from 1.1.1: the bars before it are −1, −2…
            // Zoomed out they thin out, as in Live: numbers every 1, 2, 4, 8… bars (whatever keeps them apart),
            // bar lines at the closest step that isn't a blur, and beat lines fading out as beats get narrow.
            let bpb = sequence.barLength
            let barPixels = beatWidth * CGFloat(bpb)
            let labelStep = ChordLaneView.barStep(barPixels: barPixels, minimumSpacing: 44)
            let lineStep = ChordLaneView.barStep(barPixels: barPixels, minimumSpacing: 10)
            let countWidth = beatWidth * CGFloat(sequence.countUnit)
            let beatOpacity = min(max((countWidth - 10) / 8, 0), 1) * 0.1
            let firstBar = Int(floor((Double(visible.lowerBound / beatWidth) - origin) / bpb))
            let lastBar = Int(ceil((Double(visible.upperBound / beatWidth) - origin) / bpb))
            let firstLine = Int(floor(Double(firstBar) / Double(lineStep))) * lineStep
            ForEach(Array(stride(from: firstLine, through: max(firstLine, lastBar), by: lineStep)), id: \.self) { bar in
                let barStart = origin + Double(bar) * bpb
                let x = CGFloat(barStart) * beatWidth
                let isNumbered = bar % labelStep == 0
                if barStart >= -0.001 && barStart <= sequence.lengthInBeats {
                    Rectangle()
                        .fill(Color.white.opacity(isNumbered ? 0.35 : 0.18))
                        .frame(width: 1, height: laneHeight - 18)
                        .offset(x: x, y: 0)
                        .allowsHitTesting(false)
                    // Bar 1 is labelled by the 1.1.1 flag
                    if bar != 0 && isNumbered {
                        Text("\(bar >= 0 ? bar + 1 : bar)")
                            .font(.caption2)
                            .opacity(bar < 0 ? 0.4 : 0.6)
                            .offset(x: x + 4, y: laneHeight - 16)
                            .allowsHitTesting(false)
                    }
                }
                if beatOpacity > 0 {
                    // The bar's beats in the time signature's unit (eighths in 7/8)
                    ForEach(1..<max(1, sequence.timeSignature.numerator), id: \.self) { beat in
                        let beatAt = barStart + Double(beat) * sequence.countUnit
                        if beatAt >= 0 && beatAt <= sequence.lengthInBeats {
                            Rectangle()
                                .fill(Color.white.opacity(beatOpacity))
                                .frame(width: 1, height: laneHeight - 48)
                                .offset(x: CGFloat(beatAt) * beatWidth, y: 30)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }

            // The grid between the beats (finer than a beat, or triplets), faintly, while its lines aren't too close
            let grid = editor.snap
            let gridCounts = grid / sequence.countUnit
            if grid > 0, grid * Double(beatWidth) >= 6,
               abs(gridCounts - gridCounts.rounded()) > 1e-9 || gridCounts < 1 {
                let firstStep = Int(floor((Double(visible.lowerBound / beatWidth) - origin) / grid))
                let lastStep = Int(ceil((Double(visible.upperBound / beatWidth) - origin) / grid))
                ForEach(firstStep..<max(firstStep, lastStep + 1), id: \.self) { step in
                    let beat = origin + Double(step) * grid
                    let counts = (beat - origin) / sequence.countUnit
                    let offBeat = abs(counts - counts.rounded()) > 1e-6
                    if offBeat && beat >= 0 && beat <= sequence.lengthInBeats {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 1, height: laneHeight - 48)
                            .offset(x: CGFloat(beat) * beatWidth, y: 30)
                            .allowsHitTesting(false)
                    }
                }
            }

            if let audio = sequence.audio {
                WaveformRow(sequence: sequence, editor: editor, audio: audio, beatWidth: beatWidth, visible: visible, height: waveformHeight)
                    .offset(y: waveformTop)
            }
            
            // Recorded takes
            ForEach(sequence.takes) { take in
                if let span = LaneSpan(take.startBeat, max(take.endBeat, take.startBeat + Double(8 / beatWidth)),
                                       beatWidth: beatWidth, visible: visible) {
                // Box and contents as separate shapes (a box as a background stopped drawing when zoomed in)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red.opacity(take.isMuted ? 0.15 : 0.4))
                    .frame(width: span.width, height: takesHeight)
                    .offset(x: span.x, y: takesTop)
                HStack(spacing: 4) {
                    Image(systemName: take.isMuted ? "speaker.slash" : "mic.fill")
                        .font(.system(size: 10))
                    Text(take.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(width: span.width, height: takesHeight, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button(take.isMuted ? "Unmute" : "Mute") { session.setTakeMuted(take.id, !take.isMuted) }
                    Divider()
                    Button("Delete Take", role: .destructive) { session.removeTake(take.id) }
                }
                .offset(x: span.x, y: takesTop)
                }
            }

            // On top: the start and end markers, and the loop brace. In the lane itself rather than an overlay,
            // which stopped drawing its shapes when zoomed in
            songMarkers(width: width, visible: visible)
            loopBrace(visible: visible)
        }
        .frame(width: width, height: laneHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(laneClick)
        .coordinateSpace(name: ChordLaneView.contentSpace)
        .onContinuousHover(coordinateSpace: .named(ChordLaneView.contentSpace)) { phase in
            if case .active(let point) = phase {
                pointer.beat = Double(point.x / beatWidth)
            }
        }
        .contextMenu {
            Button("Set 1.1.1 Here") { setStart(snappedStart(pointer.beat, free: false)) }
            Button("Set End Here") { setEnd(sequence.onGrid(pointer.beat, unit: editor.snap, .toNearestOrAwayFromZero)) }
            Button("Automatic End") { session.sequence?.endBeat = nil }
                .disabled(sequence.endBeat == nil)
        }
    }

    // MARK: - Loop brace

    private enum LoopPart { case body, start, end }

    /// The loop range along the top: yellow while looping, grey when not (so it can be turned back on).
    /// Drag it to move it, drag an end to resize it (on the grid; ⌥ for free), click it to loop or not.
    @ViewBuilder
    private func loopBrace(visible: ClosedRange<CGFloat>) -> some View {
        // While it's being dragged it's drawn even off screen: a view removed mid-drag never hears the drag end,
        // which leaves the window ignoring every click after
        if let range = loopDrag ?? sequence.loopRange,
           let span = LaneSpan(range.start, range.end, beatWidth: beatWidth,
                               visible: loopDrag != nil ? -CGFloat.infinity...CGFloat.infinity : visible, margin: 0) {
            let handle = min(8, span.width / 3)
            let colour = sequence.isLooping ? Color.yellow : Color.gray
            // Lines down the lane at each end, so the looped stretch reads over the chords and the waveform
            // (plain rectangles ignoring clicks draw fine at any zoom, like the bar lines)
            if !span.startCut {
                Rectangle()
                    .fill(colour.opacity(sequence.isLooping ? 0.6 : 0.35))
                    .frame(width: 1, height: laneHeight - 18)
                    .offset(x: span.x)
                    .allowsHitTesting(false)
                LoopEnd(pointsRight: true)
                    .fill(colour.opacity(sequence.isLooping ? 0.95 : 0.6))
                    .frame(width: 8, height: 12)
                    .offset(x: span.x)
            }
            if !span.endCut {
                Rectangle()
                    .fill(colour.opacity(sequence.isLooping ? 0.6 : 0.35))
                    .frame(width: 1, height: laneHeight - 18)
                    .offset(x: span.x + span.width - 1)
                    .allowsHitTesting(false)
                LoopEnd(pointsRight: false)
                    .fill(colour.opacity(sequence.isLooping ? 0.95 : 0.6))
                    .frame(width: 8, height: 12)
                    .offset(x: span.x + span.width - 8)
            }
            // Separate plain shapes: the bar, then the body and ends to grab, on top
            // (No allowsHitTesting: with it this stopped drawing when zoomed in. The body above takes the clicks.)
            RoundedRectangle(cornerRadius: 2)
                .fill(sequence.isLooping ? Color.yellow.opacity(0.85) : Color.gray.opacity(0.55))
                .frame(width: span.width, height: 6)
                .offset(x: span.x)
            Color.clear
                .frame(width: span.width, height: 10)
                .contentShape(Rectangle())
                .gesture(loopGesture(.body))
                .help(sequence.isLooping
                      ? "The loop: drag to move it, drag an end to resize it (⌥ for free). Click to stop looping (⌘L)."
                      : "The loop, turned off: click to loop it again (⌘L). Drag to move it, drag an end to resize it.")
                .offset(x: span.x)
            if !span.startCut {
                loopHandle(.start, width: handle)
                    .offset(x: span.x)
            }
            if !span.endCut {
                loopHandle(.end, width: handle)
                    .offset(x: span.x + span.width - handle)
            }
        }
    }

    /// The corner at each end of the loop: a right-angled triangle hanging from the bar, its upright side on
    /// the loop's edge, pointing in.
    private struct LoopEnd: SwiftUI.Shape {
        var pointsRight: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let edge = pointsRight ? rect.minX : rect.maxX
            let tip = pointsRight ? rect.maxX : rect.minX
            path.move(to: CGPoint(x: edge, y: rect.minY))
            path.addLine(to: CGPoint(x: tip, y: rect.minY))
            path.addLine(to: CGPoint(x: edge, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    private func loopHandle(_ part: LoopPart, width: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: 12)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(loopGesture(part))
    }

    private func loopGesture(_ part: LoopPart) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(ChordLaneView.contentSpace))
            .onChanged { value in
                guard let original = sequence.loopRange,
                      loopDrag != nil || abs(value.translation.width) >= 3 else { return }
                let free = NSEvent.modifierFlags.contains(.option) || editor.snap == 0
                let snap = { (beat: Double) in free ? beat : sequence.onGrid(beat, unit: editor.snap, .toNearestOrAwayFromZero) }
                let shortest = free ? 1.0 / 16 : editor.snap
                let delta = Double(value.translation.width / beatWidth)
                let length = sequence.lengthInBeats
                switch part {
                case .body:
                    let start = min(max(0, snap(original.start + delta)), length - original.length)
                    loopDrag = BeatRange(start, start + original.length)
                case .start:
                    loopDrag = BeatRange(max(0, min(snap(original.start + delta), original.end - shortest)), original.end)
                case .end:
                    loopDrag = BeatRange(original.start, min(length, max(snap(original.end + delta), original.start + shortest)))
                }
            }
            .onEnded { _ in
                if let loopDrag {
                    // Moving or resizing it leaves looping as it was
                    session.sequence?.loopRange = loopDrag
                } else if part == .body {
                    session.sequence?.isLooping.toggle()
                }
                loopDrag = nil
            }
    }

    // MARK: - Start (1.1.1) and end markers

    /// The area before 1.1.1 and after the end, shaded, and a flag for each in the bar-number strip.
    /// Drag a flag to move it (⌥ for free); right-click anywhere in the lane to set either there.
    private func songMarkers(width: CGFloat, visible: ClosedRange<CGFloat>) -> some View {
        let startX = CGFloat(origin) * beatWidth
        let endX = CGFloat(songEnd) * beatWidth
        let isAutomaticEnd = sequence.endBeat == nil && markerDrag?.marker != .end
        return ZStack(alignment: .topLeading) {
            if let before = LaneSpan(0, origin, beatWidth: beatWidth, visible: visible) {
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: before.width, height: laneHeight)
                    .offset(x: before.x)
                    .allowsHitTesting(false)
            }
            if let after = LaneSpan(songEnd, sequence.lengthInBeats, beatWidth: beatWidth, visible: visible) {
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: after.width, height: laneHeight)
                    .offset(x: after.x)
                    .allowsHitTesting(false)
            }
            Rectangle()
                .fill(markerColour.opacity(0.8))
                .frame(width: 1.5, height: laneHeight)
                .offset(x: startX)
                .allowsHitTesting(false)
            Rectangle()
                .fill(markerColour.opacity(isAutomaticEnd ? 0.35 : 0.8))
                .frame(width: 1.5, height: laneHeight)
                .offset(x: endX - 1.5)
                .allowsHitTesting(false)

            markerFlag("start", marker: .start, faded: false)
                .offset(x: startX, y: laneHeight - 18)
                .help("Where bar 1 beat 1 is: bars, beats and the grid count from here. Drag it (it sticks to warp markers unless Snap is off or you hold ⌥), or right-click in the lane: Set 1.1.1 Here.")
            markerFlag("End", marker: .end, faded: isAutomaticEnd)
                .contextMenu {
                    Button("Automatic End") { session.sequence?.endBeat = nil }
                        .disabled(sequence.endBeat == nil)
                }
                .help(isAutomaticEnd
                      ? "Where playback stops: for now, the end of the bar the last thing ends in. Drag it to set the end yourself."
                      : "Where playback stops. Drag to move it; right-click for Automatic End.")
                .offset(x: endX - 34, y: laneHeight - 18)
        }
    }

    private func markerFlag(_ title: String, marker: SongMarker, faded: Bool) -> some View {
        // A shape with the title on it (not a background, which stopped drawing when zoomed in)
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(markerColour.opacity(faded ? 0.5 : 1))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
        }
        .frame(width: 34, height: 16)
        .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(ChordLaneView.contentSpace))
                .onChanged { value in
                    let free = NSEvent.modifierFlags.contains(.option)
                    let original = marker == .start ? sequence.startBeat : sequence.songEnd
                    let beat = original + Double(value.translation.width / beatWidth)
                    switch marker {
                    case .start:
                        markerDrag = (.start, min(max(0, snappedStart(beat, free: free)), sequence.songEnd - 1))
                    case .end:
                        let end = free ? beat : sequence.onGrid(beat, unit: editor.snap, .toNearestOrAwayFromZero)
                        markerDrag = (.end, min(max(end, sequence.startBeat + 1), sequence.lengthInBeats))
                    }
                }
                .onEnded { _ in
                    if let markerDrag {
                        markerDrag.marker == .start ? setStart(markerDrag.beat) : setEnd(markerDrag.beat)
                    }
                    markerDrag = nil
                })
    }

    /// 1.1.1 sticks to a warp marker if one's close (that's usually the downbeat); otherwise it goes exactly
    /// where it's put. (Not on the grid: the grid counts from it.) With Snap off, or ⌥, it never sticks.
    private func snappedStart(_ beat: Double, free: Bool) -> Double {
        guard !free, editor.snap > 0 else { return beat }
        if let marker = sequence.audio?.warpMarkers.map(\.beat).min(by: { abs($0 - beat) < abs($1 - beat) }),
           CGFloat(abs(marker - beat)) * beatWidth <= 10 {
            return marker
        }
        return beat
    }

    private func setStart(_ beat: Double) {
        guard let sequence = session.sequence else { return }
        session.sequence?.startBeat = min(max(0, beat), sequence.songEnd - 1)
    }

    private func setEnd(_ beat: Double) {
        guard let sequence = session.sequence else { return }
        session.sequence?.endBeat = min(max(beat, sequence.startBeat + 1), sequence.lengthInBeats)
    }

    /// Clicking anywhere that doesn't have its own job places the playhead (selects by the grid);
    /// dragging selects a range.
    private var laneClick: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard abs(value.translation.width) >= 3 else { return }
                editor.selectRange(from: Double(value.startLocation.x / beatWidth), to: Double(value.location.x / beatWidth),
                                   free: NSEvent.modifierFlags.contains(.option), in: sequence)
            }
            .onEnded { value in
                guard abs(value.translation.width) < 3 else { return }
                editor.select(beat: Double(value.location.x / beatWidth),
                              extend: NSEvent.modifierFlags.contains(.shift), in: sequence)
                session.seek(to: editor.selection.start)
            }
    }
}

/// The selected range. Its own view so a new selection doesn't redraw the rest of the lane.
private struct SelectionHighlight: View {
    let editor: SequenceEditorState
    let beatWidth: CGFloat
    let height: CGFloat
    let visible: ClosedRange<CGFloat>

    var body: some View {
        if let span = LaneSpan(editor.selection.start, editor.selection.end, beatWidth: beatWidth, visible: visible) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: span.width, height: height)
                .offset(x: span.x)
                .allowsHitTesting(false)
        }
    }
}

/// The moving playhead. Only this redraws every frame, not the lane.
private struct PlayingPlayhead: View {
    let editor: SequenceEditorState
    let beatWidth: CGFloat
    let height: CGFloat

    @Environment(TransportState.self) private var transport

    var body: some View {
        TimelineView(.animation) { context in
            Rectangle()
                .fill(Color.orange)
                .frame(width: 2, height: height)
                .offset(x: CGFloat(transport.position()) * beatWidth)
                .allowsHitTesting(false)
                // Only while really playing: once stopped the clock reads 0, and following that would
                // throw the view back to the start
                .onChange(of: context.date) {
                    if transport.isPlaying {
                        editor.follow(transport.position())
                    }
                }
        }
    }
}

/// Where Play will start from.
private struct StoppedPlayhead: View {
    let editor: SequenceEditorState
    let beatWidth: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.orange.opacity(0.8))
            .frame(width: 2, height: height)
            .offset(x: CGFloat(editor.selection.start) * beatWidth)
            .allowsHitTesting(false)
    }
}

extension ChordClipsLayer: Equatable {
    /// What the clips show (the analysis they read is watched separately): when none of it changes, they aren't
    /// rebuilt.
    static func == (a: ChordClipsLayer, b: ChordClipsLayer) -> Bool {
        a.editor === b.editor && a.beatWidth == b.beatWidth && a.height == b.height && a.isEditable == b.isEditable
            && a.visible == b.visible && a.sequence.chords == b.sequence.chords && a.sequence.instances == b.sequence.instances
            && a.sequence.lengthInBeats == b.sequence.lengthInBeats && a.sequence.startBeat == b.sequence.startBeat
    }
}

/// Chords as clips, DAW-style:
/// - click a chord to select it, double-click to change it (⇧-click extends the selection)
/// - drag a chord to move it, drag either edge to resize it; it trims whatever it lands on
/// - click between chords to select by the grid, drag to select any range
/// Moves snap to the grid and, magnetically, to the other chords' edges: keep dragging to pull away.
/// Hold ⌥ to ignore both.
private struct ChordClipsLayer: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState
    let beatWidth: CGFloat
    let height: CGFloat
    let isEditable: Bool
    /// The part of the lane on screen: clips are drawn only that much.
    let visible: ClosedRange<CGFloat>

    @Environment(SequenceSession.self) private var session

    /// The chord being moved or resized, where it is now.
    @State private var dragged: ChordRegion?
    @State private var isSelectingRange = false

    private enum Part { case body, start, end }

    static let space = "chord-clips"
    /// How close (in points) an edge has to come to another chord's edge to stick to it.
    private let magnet: CGFloat = 10
    /// Below this (in points) a press is a click, not a drag.
    private let clickSlop: CGFloat = 3

    /// The chords as they'd be with the drag applied, so neighbours show their trims live.
    private var displayed: [ChordRegion] {
        guard let dragged else { return sequence.chords }
        var preview = sequence
        preview.place(dragged)
        return preview.chords
    }

    var body: some View {
        let width = CGFloat(sequence.lengthInBeats) * beatWidth
        // Pieces split off during a drag have new ids, so fall back to the symbol for their names
        let bySymbol = Dictionary(sequence.chords.compactMap { region in
            editor.analysis.chords[region.id].map { (region.symbol, ($0, editor.analysis.scales[region.id])) }
        }, uniquingKeysWith: { first, _ in first })

        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .gesture(backgroundGesture, including: isEditable ? .all : .none)

            // Only the chords on screen (and one being dragged): each one SwiftUI has to keep track of costs time on
            // every update, and a song has hundreds
            let lowerBeat = Double(visible.lowerBound / beatWidth), upperBeat = Double(visible.upperBound / beatWidth)
            ForEach(displayed.filter { $0.range.end >= lowerBeat && $0.range.start <= upperBeat || $0.id == dragged?.id }) { region in
                // The one being dragged is always drawn, so the drag carries on if it leaves the screen
                let isDragged = dragged?.id == region.id
                // No margin: a long chord's name stays at the left of the screen when its start is scrolled off
                if let span = LaneSpan(region.range.start, region.range.end, beatWidth: beatWidth,
                                       visible: isDragged ? -CGFloat.infinity...CGFloat.infinity : visible, margin: 0) {
                let parsed = editor.analysis.chords[region.id] ?? bySymbol[region.symbol]?.0
                let scale = editor.analysis.scales[region.id] ?? bySymbol[region.symbol]?.1
                let clipWidth = max(0, span.width - 2)
                let handle = min(7, clipWidth / 4)
                // The box (and the outline while dragging) as plain shapes of their own. Drawn as a background
                // of the name with the outline as an overlay, the box disappeared far along a zoomed-in lane.
                // A pattern's repeats are fainter, as in Live (they're the same chords, edited together)
                let isRepeat = (sequence.chordSources[region.id]?.round ?? 0) > 0
                RoundedRectangle(cornerRadius: 4)
                    .fill(parsed == nil ? Color.red.opacity(0.4) : Color.blue.opacity(isDragged ? 0.55 : isRepeat ? 0.2 : 0.35))
                    .frame(width: clipWidth, height: 46)
                    .offset(x: span.x + 1, y: 30)
                if isDragged {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                        .frame(width: clipWidth, height: 46)
                        .offset(x: span.x + 1, y: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(parsed?.description ?? region.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    if let scale {
                        Text(scale.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .opacity(0.6)
                    }
                }
                .padding(.horizontal, 6)
                // The names truncate to fit
                .frame(width: clipWidth, height: 46, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(clipGesture(region, .body), including: isEditable ? .all : .none)
                // Resize handles only on the clip's real edges, not where it's cut off at the screen's edge
                .overlay(alignment: .leading) { if !span.startCut { edgeHandle(region, .start, width: handle) } }
                .overlay(alignment: .trailing) { if !span.endCut { edgeHandle(region, .end, width: handle) } }
                .offset(x: span.x + 1, y: 30)
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
    }

    @ViewBuilder
    private func edgeHandle(_ region: ChordRegion, _ part: Part, width: CGFloat) -> some View {
        // Always there (disabled while playing), not added and removed: a handle removed while it's pressed (Play
        // pressed mid-drag) would leave the window ignoring clicks
        Color.clear
            .frame(width: width, height: 46)
            .contentShape(Rectangle())
            .onHover { inside in
                guard isEditable else { return }
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(clipGesture(region, part), including: isEditable ? .all : .none)
    }

    // MARK: - Gestures

    /// One gesture for click and drag, so clicks act at once (no waiting to see if it's a double-click).
    private func clipGesture(_ region: ChordRegion, _ part: Part) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard dragged != nil || abs(value.translation.width) >= clickSlop else { return }
                // Measured from the chord as it was before the drag, so it stays under the mouse
                let original = sequence.chords.first { $0.id == region.id } ?? region
                dragged = moved(original, part, by: Double(value.translation.width / beatWidth))
            }
            .onEnded { _ in
                if let dragged {
                    session.sequence?.place(dragged)
                    self.dragged = nil
                    if let sequence = session.sequence {
                        editor.select(dragged.range, extend: false, in: sequence)
                    }
                } else {
                    editor.select(region.range, extend: NSEvent.modifierFlags.contains(.shift), in: sequence)
                    session.seek(to: editor.selection.start)
                    if clickCount >= 2 { editor.showsPalette = true }
                }
            }
    }

    private var backgroundGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard isSelectingRange || abs(value.translation.width) >= clickSlop else { return }
                isSelectingRange = true
                editor.selectRange(from: Double(value.startLocation.x / beatWidth), to: Double(value.location.x / beatWidth),
                                   free: NSEvent.modifierFlags.contains(.option), in: sequence)
            }
            .onEnded { value in
                if !isSelectingRange {
                    editor.select(beat: Double(value.location.x / beatWidth),
                                  extend: NSEvent.modifierFlags.contains(.shift), in: sequence)
                    session.seek(to: editor.selection.start)
                    if clickCount >= 2 { editor.showsPalette = true }
                }
                isSelectingRange = false
            }
    }

    private var clickCount: Int {
        NSApp.currentEvent?.clickCount ?? 1
    }

    // MARK: - Snapping

    /// The chord after dragging `part` by `delta` beats, snapped.
    private func moved(_ original: ChordRegion, _ part: Part, by delta: Double) -> ChordRegion {
        let free = NSEvent.modifierFlags.contains(.option)
        let edges = magnetEdges(excluding: original.id)
        let minimum = free ? 1.0 / 16 : 0.25
        var result = original
        switch part {
        case .body:
            let length = original.range.length
            var start = original.range.start + delta
            if !free {
                // Either edge can stick to a neighbour; otherwise the start goes on the grid
                let pulls = edges.flatMap { [$0 - start, $0 - (start + length)] }
                if let pull = pulls.min(by: { abs($0) < abs($1) }), CGFloat(abs(pull)) * beatWidth <= magnet {
                    start += pull
                } else {
                    start = onGrid(start)
                }
            }
            start = min(max(0, start), sequence.lengthInBeats - length)
            result.range = BeatRange(start, start + length)
        case .start:
            let start = snapped(original.range.start + delta, free: free, edges: edges)
            result.range = BeatRange(max(0, min(start, original.range.end - minimum)), original.range.end)
        case .end:
            let end = snapped(original.range.end + delta, free: free, edges: edges)
            result.range = BeatRange(original.range.start, min(sequence.lengthInBeats, max(end, original.range.start + minimum)))
        }
        return result
    }

    private func snapped(_ beat: Double, free: Bool, edges: [Double]) -> Double {
        guard !free else { return beat }
        if let nearest = edges.min(by: { abs($0 - beat) < abs($1 - beat) }), CGFloat(abs(nearest - beat)) * beatWidth <= magnet {
            return nearest
        }
        return onGrid(beat)
    }

    /// The grid runs from 1.1.1 (the start marker).
    private func onGrid(_ beat: Double) -> Double {
        sequence.onGrid(beat, unit: editor.snap, .toNearestOrAwayFromZero)
    }

    /// The other chords' edges, the start and end markers, and the ends of the sequence.
    private func magnetEdges(excluding id: UUID) -> [Double] {
        sequence.chords.filter { $0.id != id }.flatMap { [$0.range.start, $0.range.end] }
            + [0, sequence.lengthInBeats, sequence.startBeat, sequence.songEnd]
    }
}

/// The whole sequence in miniature with the part on screen as a thumb: drag it to scroll, drag its
/// ends to zoom, click elsewhere to jump there. Double-click to fit the whole sequence.
/// The part of `start..<end` (beats) that's on screen, in lane x. Long shapes are drawn only this much, so
/// zooming right in (to single samples) doesn't build views millions of points wide. No margin by default:
/// far along a zoomed-in lane, shapes that start off the left of the screen weren't drawn at all.
/// Whether a mouse button is down in this app: from its events, as they're handled (so it agrees with the gestures).
enum MouseButtons {
    private(set) static var isDown = false
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                                              .otherMouseDown, .otherMouseUp]) { event in
            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: isDown = true
            default: isDown = false
            }
            return event
        }
    }
}

/// The beats drawn while the mouse was down (a plain reference: remembering it isn't a change to redraw for).
final class PressedRange {
    var beats: ClosedRange<Double>?
}

struct LaneSpan {
    var x: CGFloat
    var width: CGFloat
    /// Whether the real start or end is off screen (so it isn't an edge to grab).
    var startCut: Bool
    var endCut: Bool

    init?(_ start: Double, _ end: Double, beatWidth: CGFloat, visible: ClosedRange<CGFloat>, margin: CGFloat = 0) {
        let from = CGFloat(start) * beatWidth, to = CGFloat(end) * beatWidth
        let left = max(from, visible.lowerBound - margin), right = min(to, visible.upperBound + margin)
        guard right > left else { return nil }
        x = left
        width = right - left
        startCut = left > from
        endCut = right < to
    }
}

private struct LaneOverview: View {
    let editor: SequenceEditorState
    let lengthInBeats: Double
    let isPlaying: Bool

    /// The view when the drag began.
    @State private var dragOrigin: (start: Double, end: Double)?

    private enum Part { case body, start, end }
    private static let space = "lane-overview"

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / CGFloat(max(lengthInBeats, 1))
            let start = editor.viewStart
            let end = min(lengthInBeats, start + editor.visibleBeats)
            let thumbWidth = max(16, CGFloat(end - start) * scale)
            let handle = min(8, thumbWidth / 3)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            // Centre the view on the click, and follow the mouse from there
                            editor.scroll(to: Double(value.location.x / scale) - editor.visibleBeats / 2)
                            editor.viewMovedByHand()
                        }
                        .onEnded { _ in
                            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { editor.showAll() }
                        })

                Capsule()
                    .fill(Color.primary.opacity(dragOrigin == nil ? 0.3 : 0.45))
                    .frame(width: thumbWidth)
                    .contentShape(Rectangle())
                    .gesture(drag(.body, scale: scale))
                    .overlay(alignment: .leading) { edge(.start, width: handle, scale: scale) }
                    .overlay(alignment: .trailing) { edge(.end, width: handle, scale: scale) }
                    .offset(x: min(CGFloat(start) * scale, geometry.size.width - thumbWidth))
            }
            .coordinateSpace(name: Self.space)
        }
        .frame(height: 10)
        .help("Drag to scroll, drag the ends to zoom, double-click to see everything. On a trackpad, swipe the lane to scroll and pinch to zoom. Scrolling while playing stops following the playhead until you next press Play.")
    }

    private func edge(_ part: Part, width: CGFloat, scale: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(drag(part, scale: scale))
    }

    private func drag(_ part: Part, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let origin = dragOrigin ?? (editor.viewStart, editor.viewStart + editor.visibleBeats)
                dragOrigin = origin
                let delta = Double(value.translation.width / scale)
                editor.viewMovedByHand()
                switch part {
                case .body: editor.scroll(to: origin.start + delta)
                case .start: editor.show(from: min(origin.start + delta, origin.end - 0.25), to: origin.end, keeping: .end)
                case .end: editor.show(from: origin.start, to: max(origin.end + delta, origin.start + 0.25), keeping: .start)
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

/// Catches trackpad and mouse-wheel scrolling and pinching over the lane, without getting in the way
/// of clicks (it never takes part in hit testing; it watches the window's events instead).
private struct ScrollCatcher: NSViewRepresentable {
    /// The event, and its x in the view.
    var onScroll: (NSEvent, CGFloat) -> Void
    var onMagnify: (CGFloat, CGFloat) -> Void

    final class CatcherView: NSView {
        var onScroll: ((NSEvent, CGFloat) -> Void)?
        var onMagnify: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                if event.type == .magnify {
                    self.onMagnify?(event.magnification, point.x)
                } else {
                    self.onScroll?(event, point.x)
                }
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.removeMonitor()
    }
}

/// The recording drawn in beat time (so it lines up with the grid), with warp markers, Live-style:
/// - double-click the waveform to add a marker, double-click a marker to remove it
/// - drag a marker to stretch the audio onto a beat (snaps to sixteenths; ⌥ for free)
/// - ⇧-drag a marker to slide it along the audio without moving the audio
/// - drag the waveform itself to grab that moment and pull it onto a beat
/// Everything redraws live while dragging; the audio re-renders when you let go.
private struct WaveformRow: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState
    let audio: AudioTrack
    let beatWidth: CGFloat
    /// The part of the lane on screen, in lane x coordinates.
    let visible: ClosedRange<CGFloat>
    let height: CGFloat

    @Environment(SequenceSession.self) private var session

    /// A marker being dragged (an existing one, or one just made with a double-click).
    @State private var dragging: WarpMarker?
    @State private var hovered: UUID?
    /// What a press on the waveform turned out to be.
    @State private var gesture: WaveformGesture?
    /// When and where the last click ended, to tell a double-click (the system's click count isn't
    /// reliable by the time the gesture hears about the press).
    @State private var lastClick: (time: Date, x: CGFloat)?

    private enum WaveformGesture {
        /// A click so far (it becomes a range if it moves).
        case click
        case range
        /// A double-click made this marker; dragging moves it.
        case newMarker(WarpMarker)
    }

    /// The markers as they'd be with the drag applied, so the waveform follows the mouse.
    private var liveMarkers: [WarpMarker] {
        guard let dragging else { return audio.warpMarkers }
        return (audio.warpMarkers.filter { $0.id != dragging.id } + [dragging]).sorted { $0.beat < $1.beat }
    }

    var body: some View {
        let map = WarpMap(markers: liveMarkers, tempo: audio.tempo)
        let left = max(0, visible.lowerBound)
        let width = max(1, visible.upperBound - left)

        ZStack(alignment: .topLeading) {
            // Each section's own tempo, between markers, like Seg. BPM in Live. Under the waveform (which is
            // see-through around it) so clicks still reach the waveform; not allowsHitTesting(false), which
            // stopped it drawing when zoomed in
            ForEach(Array(zip(liveMarkers, liveMarkers.dropFirst())), id: \.0.id) { a, b in
                let start = CGFloat(a.beat) * beatWidth, end = CGFloat(b.beat) * beatWidth
                if end - start > 56 && end >= left && start <= left + width {
                    ZStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.45))
                        Text(String(format: "%.1f", (b.beat - a.beat) / (b.sourceTime - a.sourceTime) * 60))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                    .frame(width: 40, height: 14)
                    .offset(x: max(start, left) + 8, y: 13)
                }
            }

            if let peaks = session.peaks {
                let source = session.sourceAudio
                Canvas { context, size in
                    let middle = size.height / 2
                    let y = { (value: Float) in middle - CGFloat(value) * middle * 0.95 }
                    var path = Path()
                    // Zoomed in, the overview isn't detailed enough: the samples themselves, as each column's
                    // range, or (closer still) a line through them
                    var lastLinePoint: CGPoint?
                    for column in stride(from: 0, to: size.width, by: 1) {
                        let x = left + column
                        let start = map.sourceTime(atBeat: Double(x / beatWidth))
                        let end = map.sourceTime(atBeat: Double((x + 1) / beatWidth))
                        guard end > 0, start < audio.reference.duration, start.isFinite, end.isFinite else {
                            lastLinePoint = nil
                            continue
                        }
                        if let source, (end - start) * source.sampleRate < Double(peaks.samplesPerBlock) {
                            let position = start * source.sampleRate
                            if (end - start) * source.sampleRate < 1 {
                                let point = CGPoint(x: column, y: y(Self.sample(source, at: position)))
                                if let lastLinePoint {
                                    path.move(to: lastLinePoint)
                                    path.addLine(to: point)
                                }
                                lastLinePoint = point
                            } else {
                                let (low, high) = Self.range(source, from: Int(position), to: Int(ceil(end * source.sampleRate)))
                                path.move(to: CGPoint(x: column, y: y(high)))
                                path.addLine(to: CGPoint(x: column, y: y(low) + 0.5))
                                lastLinePoint = nil
                            }
                            continue
                        }
                        lastLinePoint = nil
                        let (low, high) = peaks.range(from: start, to: end)
                        path.move(to: CGPoint(x: column, y: y(high)))
                        path.addLine(to: CGPoint(x: column, y: y(low) + 0.5))
                    }
                    context.stroke(path, with: .color(.cyan.opacity(audio.isMuted ? 0.25 : 0.75)), lineWidth: 1)
                }
                .frame(width: width, height: height)
                // Clickable where it's drawn: the shape and gesture go on before it's moved into place
                // (after, they'd stay at the start of the lane and miss clicks once it's scrolled)
                .contentShape(Rectangle())
                .gesture(waveformDrag(map: map, left: left))
                .offset(x: left)
            } else {
                Text(statusText)
                    .font(.caption)
                    .opacity(0.6)
                    .frame(width: 400, height: height, alignment: .leading)
                    .padding(.leading, 8)
                    .offset(x: left)
            }

            ForEach(liveMarkers) { marker in
                let x = CGFloat(marker.beat) * beatWidth
                // The one being dragged is always drawn: a view removed mid-drag never hears the drag end, which
                // leaves the window ignoring every click after
                if (x >= left - 10 && x <= left + width + 10) || dragging?.id == marker.id {
                    let isActive = dragging?.id == marker.id || hovered == marker.id
                    // The line is only drawn: clicks on it go to the waveform (playhead, ranges, new markers)
                    Rectangle()
                        .fill(isActive ? Color.orange : Color.yellow)
                        .frame(width: isActive ? 2 : 1.5, height: height - 11)
                        .offset(x: x - (isActive ? 1 : 0.75), y: 11)
                        .allowsHitTesting(false)
                    // Only the arrow picks the marker up
                    WarpFlag(isActive: isActive)
                        .onHover { hovered = $0 ? marker.id : (hovered == marker.id ? nil : hovered) }
                        .gesture(markerDrag(marker, map: map))
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            // Once the drag it's also part of has heard the mouse come up (removed first, the
                            // drag would never end, and the window would ignore clicks)
                            DispatchQueue.main.async { session.sequence?.audio?.removeMarker(marker.id) }
                        })
                        .contextMenu {
                            Button("Set 1.1.1 Here") { session.sequence?.startBeat = max(0, marker.beat) }
                            Divider()
                            // Live's Warp From Here (Straight): the tempo of the selection (or, with none, of the
                            // stretch up to this marker) carried on to the end of the recording
                            let from = editor.selection.length > 0 ? "the selection" : "the stretch before it"
                            if let bpm = warpFromHereTempo(marker) {
                                Button("Warp From Here (\(String(format: "%.2f", bpm)) BPM, from \(from))") {
                                    session.sequence?.audio?.warpStraight(from: marker.id, bpm: bpm)
                                }
                            } else {
                                Button("Warp From Here (select a warped stretch first)") {}
                                    .disabled(true)
                            }
                            Button("Delete Warp Marker") { session.sequence?.audio?.removeMarker(marker.id) }
                                .disabled(liveMarkers.count <= 1)
                        }
                        .help(liveMarkers.count <= 1
                              ? "Where the recording sits on the grid: drag to move it all (⌥ free); ⇧-drag to slide the audio under it"
                              : "Drag to stretch onto a beat (⌥ free). ⇧-drag to slide the audio under it, to line up a different hit. Double-click to remove.")
                        // Moved into place last, so it's grabbed where it's drawn
                        .offset(x: x - 6)
                }
            }

        }
        .frame(height: height, alignment: .topLeading)
        .coordinateSpace(name: WaveformRow.space)
    }
    
    /// The tempo Warp From Here carries on from a marker: the selection's, as it's warped now, or with nothing
    /// selected, that of the stretch up to the marker.
    private func warpFromHereTempo(_ marker: WarpMarker) -> Double? {
        guard let audio = sequence.audio else { return nil }
        if editor.selection.length > 0 {
            return audio.warpedTempo(over: editor.selection)
        }
        return audio.tempoBefore(marker.id)
    }

    /// Coordinates for dragging: lane x, fixed while markers move.
    static let space = "warp-row"

    /// The recording at a fractional sample position (channels mixed), interpolated between samples.
    private static func sample(_ audio: AudioData, at position: Double) -> Float {
        let index = Int(floor(position))
        guard index >= 0, index + 1 < audio.frameCount, !audio.channels.isEmpty else { return 0 }
        let fraction = Float(position - Double(index))
        var value: Float = 0
        for channel in audio.channels {
            value += channel[index] * (1 - fraction) + channel[index + 1] * fraction
        }
        return value / Float(audio.channels.count)
    }

    /// The lowest and highest of the recording's samples (channels mixed) from `start` to `end`.
    private static func range(_ audio: AudioData, from start: Int, to end: Int) -> (Float, Float) {
        let lower = max(0, start), upper = min(audio.frameCount, max(end, start + 1))
        guard lower < upper, !audio.channels.isEmpty else { return (0, 0) }
        var low: Float = 0, high: Float = 0
        let scale = 1 / Float(audio.channels.count)
        for index in lower..<upper {
            var value: Float = 0
            for channel in audio.channels { value += channel[index] }
            value *= scale
            low = min(low, value)
            high = max(high, value)
        }
        return (low, high)
    }
    
    /// Stretch: the marker keeps its moment in the audio and moves to a new beat.
    /// Slide (⇧), as in Live: the marker stays on its beat and the audio slides underneath it, following the
    /// mouse, so a different moment lands on that beat (each side stretches to fit).
    /// Measured in the row's fixed coordinates against where the marker started, so what you grabbed
    /// stays under the mouse.
    private func markerDrag(_ marker: WarpMarker, map: WarpMap) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(WaveformRow.space))
            .onChanged { value in
                let flags = NSEvent.modifierFlags
                // The marker as it was before this drag (the one on screen has already moved)
                let original = audio.warpMarkers.first { $0.id == marker.id } ?? marker
                var moved = original
                if flags.contains(.shift) {
                    // How much audio a beat holds where the marker is, as it was before the drag
                    let before = audio.map
                    let secondsPerBeat = (before.sourceTime(atBeat: original.beat + 0.01)
                        - before.sourceTime(atBeat: original.beat - 0.01)) / 0.02
                    // Dragging right brings earlier audio under the marker
                    moved.sourceTime = original.sourceTime - Double(value.translation.width / beatWidth) * secondsPerBeat
                    dragging = slideClamped(moved)
                } else {
                    let grab = value.startLocation.x - CGFloat(original.beat) * beatWidth
                    moved.beat = snap(Double((value.location.x - grab) / beatWidth), free: flags.contains(.option))
                    dragging = clamped(moved)
                }
            }
            .onEnded { _ in commitDrag() }
    }

    /// Keeps a sliding marker's moment in the audio between its neighbours' (and inside the recording).
    private func slideClamped(_ marker: WarpMarker) -> WarpMarker {
        let others = audio.warpMarkers.filter { $0.id != marker.id }
        let before = others.filter { $0.beat < marker.beat }.max { $0.beat < $1.beat }
        let after = others.filter { $0.beat > marker.beat }.min { $0.beat < $1.beat }
        var result = marker
        result.sourceTime = min(max(result.sourceTime, (before?.sourceTime ?? -.infinity) + 0.005), (after?.sourceTime ?? .infinity) - 0.005)
        result.sourceTime = min(max(result.sourceTime, 0), audio.reference.duration)
        return result
    }

    /// As in the rest of the lane: click to place the playhead, drag to select a range. Double-click to
    /// add a warp marker there, and keep holding to drag it into place. One gesture, so clicks act at once.
    private func waveformDrag(map: WarpMap, left: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(WaveformRow.space))
            .onChanged { value in
                if gesture == nil {
                    gesture = .click
                    let isDoubleClick = lastClick.map {
                        Date().timeIntervalSince($0.time) <= NSEvent.doubleClickInterval && abs($0.x - value.startLocation.x) <= 5
                    } ?? false
                    lastClick = nil
                    if isDoubleClick {
                        let beat = Double(value.startLocation.x / beatWidth)
                        let marker = WarpMarker(sourceTime: map.sourceTime(atBeat: beat), beat: beat)
                        if session.sequence?.audio?.setMarker(marker) == true {
                            gesture = .newMarker(marker)
                        }
                    }
                }
                switch gesture {
                case .newMarker(let marker):
                    guard dragging != nil || abs(value.translation.width) >= 2 else { return }
                    var moved = marker
                    moved.beat = snap(Double(value.location.x / beatWidth), free: NSEvent.modifierFlags.contains(.option))
                    dragging = clamped(moved)
                case .click:
                    guard abs(value.translation.width) >= 3 else { return }
                    gesture = .range
                    fallthrough
                case .range:
                    editor.selectRange(from: Double(value.startLocation.x / beatWidth), to: Double(value.location.x / beatWidth),
                                       free: NSEvent.modifierFlags.contains(.option), in: sequence)
                case nil:
                    break
                }
            }
            .onEnded { value in
                switch gesture {
                case .newMarker:
                    commitDrag()
                case .click, nil:
                    editor.select(beat: Double(value.location.x / beatWidth),
                                  extend: NSEvent.modifierFlags.contains(.shift), in: sequence)
                    session.seek(to: editor.selection.start)
                    lastClick = (Date(), value.location.x)
                case .range:
                    break
                }
                gesture = nil
            }
    }

    private func commitDrag() {
        if let dragging {
            session.sequence?.audio?.setMarker(dragging)
        }
        dragging = nil
    }

    /// The Snap grid (counted from 1.1.1); exactly where it's put with Snap off or ⌥.
    private func snap(_ beat: Double, free: Bool) -> Double {
        free ? beat : sequence.onGrid(beat, unit: editor.snap, .toNearestOrAwayFromZero)
    }

    /// Keeps a marker between its neighbours so the audio never runs backwards.
    private func clamped(_ marker: WarpMarker) -> WarpMarker {
        let others = audio.warpMarkers.filter { $0.id != marker.id }
        let before = others.filter { $0.sourceTime < marker.sourceTime }.max { $0.sourceTime < $1.sourceTime }
        let after = others.filter { $0.sourceTime > marker.sourceTime }.min { $0.sourceTime < $1.sourceTime }
        var result = marker
        if let before { result.beat = max(result.beat, before.beat + 0.0625) }
        if let after { result.beat = min(result.beat, after.beat - 0.0625) }
        return result
    }

    private var statusText: String {
        switch session.audioStatus {
        case .loading: return "Loading \(audio.reference.fileName)…"
        case .missing: return "\(audio.reference.fileName) can't be found. Use Locate… to find it."
        case .failed(let message): return message
        case .none, .ready: return ""
        }
    }
}

/// A warp marker: picked up by its arrow (or anywhere on its line while it's the selected one).
/// A warp marker's arrow: the handle that picks it up (its line is drawn separately and isn't clickable).
private struct WarpFlag: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 11))
            .foregroundColor(isActive ? .orange : .yellow)
            .frame(width: 12, height: 13)
            .contentShape(Rectangle())
    }
}
