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
    let sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(SequenceSession.self) private var session

    /// The height the lane has to fill.
    @State private var availableHeight: CGFloat = 0

    /// Chords and sections, plus a waveform row when there's audio and a row of takes when there are any.
    private var laneHeight: CGFloat {
        takesTop + (sequence.takes.isEmpty ? 0 : takesHeight + 4) + 20
    }
    let waveformTop: CGFloat = 84
    let takesHeight: CGFloat = 22
    /// The waveform takes whatever room the rest of the lane leaves.
    private var waveformHeight: CGFloat {
        max(60, availableHeight - waveformTop - 4 - (sequence.takes.isEmpty ? 0 : takesHeight + 4) - 20)
    }
    private var takesTop: CGFloat {
        sequence.audio == nil ? waveformTop : waveformTop + waveformHeight + 4
    }

    private var beatWidth: CGFloat {
        editor.barWidth / CGFloat(sequence.beatsPerBar)
    }

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id

        VStack(spacing: 0) {
            // The view stays put while playing; the playhead moves across it (and turns the page, if following)
            GeometryReader { geometry in
                let viewport = geometry.size.width
                let left = CGFloat(editor.viewStart) * beatWidth
                lane(visible: left...(left + viewport))
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
            .frame(minHeight: sequence.audio == nil ? laneHeight : waveformTop + 84 + (sequence.takes.isEmpty ? 0 : takesHeight + 4) + 20,
                   maxHeight: sequence.audio == nil ? laneHeight : .infinity)
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
                    .onChange(of: sequence.beatsPerBar) { updateViewport(geometry.size.width) }
            })

            LaneOverview(editor: editor, lengthInBeats: sequence.lengthInBeats, isPlaying: isPlaying)
                .padding(.top, 4)
        }
    }

    private func updateViewport(_ width: CGFloat) {
        editor.setViewport(width: Double(width), lengthInBeats: sequence.lengthInBeats, beatsPerBar: sequence.beatsPerBar)
    }

    private func lane(visible: ClosedRange<CGFloat>) -> some View {
        let width = CGFloat(sequence.lengthInBeats) * beatWidth
        let isPlaying = playback.playingSequence == editor.id

        return ZStack(alignment: .topLeading) {
            // Selection and loop
            if !isPlaying {
                SelectionHighlight(editor: editor, beatWidth: beatWidth, height: laneHeight)
            }
            if let loop = sequence.loop {
                Rectangle()
                    .fill(Color.yellow.opacity(0.7))
                    .frame(width: CGFloat(loop.length) * beatWidth, height: 4)
                    .offset(x: CGFloat(loop.start) * beatWidth, y: 0)
                    .allowsHitTesting(false)
            }

            // Sections
            ForEach(sequence.sections) { section in
                Text(section.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(width: max(0, CGFloat(section.range.length) * beatWidth - 2), height: 20, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.purple.opacity(0.45)))
                    .offset(x: CGFloat(section.range.start) * beatWidth + 1, y: 6)
                    .allowsHitTesting(false)
            }

            // Chords, which can be moved and resized; clicking or dragging between them selects
            ChordClipsLayer(sequence: sequence, editor: editor, beatWidth: beatWidth,
                            height: waveformTop, isEditable: !isPlaying)

            // Bar lines and numbers (only those on screen)
            let firstBar = max(0, Int(visible.lowerBound / editor.barWidth))
            let lastBar = min(sequence.lengthInBars, Int(visible.upperBound / editor.barWidth) + 1)
            ForEach(firstBar..<max(firstBar, lastBar), id: \.self) { bar in
                let x = CGFloat(bar) * editor.barWidth
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: laneHeight - 18)
                    .offset(x: x, y: 0)
                    .allowsHitTesting(false)
                ForEach(1..<max(1, sequence.beatsPerBar), id: \.self) { beat in
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: laneHeight - 48)
                        .offset(x: x + CGFloat(beat) * beatWidth, y: 30)
                        .allowsHitTesting(false)
                }
                Text("\(bar + 1)")
                    .font(.caption2)
                    .opacity(0.6)
                    .offset(x: x + 4, y: laneHeight - 16)
                    .allowsHitTesting(false)
            }

            if let audio = sequence.audio {
                WaveformRow(sequence: sequence, editor: editor, audio: audio, beatWidth: beatWidth, visible: visible, height: waveformHeight)
                    .offset(y: waveformTop)
            }
            
            // Recorded takes
            ForEach(sequence.takes) { take in
                HStack(spacing: 4) {
                    Image(systemName: take.isMuted ? "speaker.slash" : "mic.fill")
                        .font(.system(size: 10))
                    Text(take.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(width: max(8, CGFloat(take.endBeat - take.startBeat) * beatWidth), height: takesHeight, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(take.isMuted ? 0.15 : 0.4)))
                .offset(x: CGFloat(take.startBeat) * beatWidth, y: takesTop)
                .contextMenu {
                    Button(take.isMuted ? "Unmute" : "Mute") { session.setTakeMuted(take.id, !take.isMuted) }
                    Divider()
                    Button("Delete Take", role: .destructive) { session.removeTake(take.id) }
                }
            }
        }
        .frame(width: width, height: laneHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(laneClick)
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

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: CGFloat(editor.selection.length) * beatWidth, height: height)
            .offset(x: CGFloat(editor.selection.start) * beatWidth)
            .allowsHitTesting(false)
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
                .onChange(of: context.date) { editor.follow(transport.position()) }
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

            ForEach(displayed) { region in
                let parsed = editor.analysis.chords[region.id] ?? bySymbol[region.symbol]?.0
                let scale = editor.analysis.scales[region.id] ?? bySymbol[region.symbol]?.1
                let clipWidth = max(0, CGFloat(region.range.length) * beatWidth - 2)
                let handle = min(7, clipWidth / 4)
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
                .frame(width: clipWidth, height: 46, alignment: .leading)
                .clipped()
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(parsed == nil ? Color.red.opacity(0.4) : Color.blue.opacity(dragged?.id == region.id ? 0.55 : 0.35)))
                .overlay {
                    if dragged?.id == region.id {
                        RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.7), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .gesture(clipGesture(region, .body), including: isEditable ? .all : .none)
                .overlay(alignment: .leading) { edgeHandle(region, .start, width: handle) }
                .overlay(alignment: .trailing) { edgeHandle(region, .end, width: handle) }
                .offset(x: CGFloat(region.range.start) * beatWidth + 1, y: 30)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
    }

    @ViewBuilder
    private func edgeHandle(_ region: ChordRegion, _ part: Part, width: CGFloat) -> some View {
        if isEditable {
            Color.clear
                .frame(width: width, height: 46)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(clipGesture(region, part))
        }
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

    private func onGrid(_ beat: Double) -> Double {
        editor.snap > 0 ? (beat / editor.snap).rounded() * editor.snap : beat
    }

    /// The other chords' edges, and the ends of the sequence.
    private func magnetEdges(excluding id: UUID) -> [Double] {
        sequence.chords.filter { $0.id != id }.flatMap { [$0.range.start, $0.range.end] } + [0, sequence.lengthInBeats]
    }
}

/// The whole sequence in miniature with the part on screen as a thumb: drag it to scroll, drag its
/// ends to zoom, click elsewhere to jump there. Double-click to fit the whole sequence.
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
    /// The marker last made or moved: its whole line can be grabbed, not just its arrow, until you click elsewhere.
    @State private var selectedMarker: UUID?
    /// What a press on the waveform turned out to be.
    @State private var gesture: WaveformGesture?

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
            if let peaks = session.peaks {
                Canvas { context, size in
                    let middle = size.height / 2
                    var path = Path()
                    for column in stride(from: 0, to: size.width, by: 1) {
                        let x = left + column
                        let start = map.sourceTime(atBeat: Double(x / beatWidth))
                        let end = map.sourceTime(atBeat: Double((x + 1) / beatWidth))
                        guard end > 0, start < audio.reference.duration, start.isFinite, end.isFinite else { continue }
                        let (low, high) = peaks.range(from: start, to: end)
                        path.move(to: CGPoint(x: column, y: middle - CGFloat(high) * middle * 0.95))
                        path.addLine(to: CGPoint(x: column, y: middle - CGFloat(low) * middle * 0.95 + 0.5))
                    }
                    context.stroke(path, with: .color(.cyan.opacity(audio.isMuted ? 0.25 : 0.75)), lineWidth: 1)
                }
                .frame(width: width, height: height)
                .offset(x: left)
                .contentShape(Rectangle())
                .gesture(waveformDrag(map: map, left: left))
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
                if x >= left - 10 && x <= left + width + 10 {
                    WarpFlag(height: height, isActive: dragging?.id == marker.id || hovered == marker.id || selectedMarker == marker.id,
                             grabsWholeLine: selectedMarker == marker.id)
                        .offset(x: x - 6)
                        .onHover { hovered = $0 ? marker.id : (hovered == marker.id ? nil : hovered) }
                        .gesture(markerDrag(marker, map: map))
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            session.sequence?.audio?.removeMarker(marker.id)
                        })
                        .contextMenu {
                            Button("Delete Warp Marker") { session.sequence?.audio?.removeMarker(marker.id) }
                                .disabled(liveMarkers.count <= 1)
                        }
                        .help(liveMarkers.count <= 1
                              ? "Where the recording sits on the grid: drag to move it all (⌥ free, ⇧ slide along the audio to put it on another hit)"
                              : "Drag to stretch onto a beat (⌥ free, ⇧ slide along the audio). Double-click to remove.")
                }
            }

            // Each section's own tempo, between markers, like Seg. BPM in Live
            ForEach(Array(zip(liveMarkers, liveMarkers.dropFirst())), id: \.0.id) { a, b in
                let start = CGFloat(a.beat) * beatWidth, end = CGFloat(b.beat) * beatWidth
                if end - start > 56 && end >= left && start <= left + width {
                    Text(String(format: "%.1f", (b.beat - a.beat) / (b.sourceTime - a.sourceTime) * 60))
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.45)))
                        .foregroundColor(.yellow)
                        .offset(x: max(start, left) + 8, y: 13)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: height, alignment: .topLeading)
        .coordinateSpace(name: WaveformRow.space)
    }
    
    /// Coordinates for dragging: lane x, fixed while markers move.
    static let space = "warp-row"
    
    /// Stretch: the marker keeps its moment in the audio and moves to a new beat.
    /// Slide (⇧): the marker moves along the audio, which stays where it is.
    /// Measured in the row's fixed coordinates against where the marker started, so the point you
    /// grabbed stays under the mouse.
    private func markerDrag(_ marker: WarpMarker, map: WarpMap) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(WaveformRow.space))
            .onChanged { value in
                selectedMarker = marker.id
                let flags = NSEvent.modifierFlags
                // The marker as it was before this drag (the one on screen has already moved)
                let original = audio.warpMarkers.first { $0.id == marker.id } ?? marker
                let grab = value.startLocation.x - CGFloat(original.beat) * beatWidth
                let raw = Double((value.location.x - grab) / beatWidth)
                var moved = original
                if flags.contains(.shift) {
                    let base = WarpMap(markers: audio.warpMarkers.filter { $0.id != marker.id }, tempo: audio.tempo)
                    moved.beat = raw
                    moved.sourceTime = base.sourceTime(atBeat: raw)
                } else {
                    moved.beat = snap(raw, free: flags.contains(.option))
                }
                dragging = clamped(moved)
            }
            .onEnded { _ in commitDrag() }
    }

    /// As in the rest of the lane: click to place the playhead, drag to select a range. Double-click to
    /// add a warp marker there, and keep holding to drag it into place. One gesture, so clicks act at once.
    private func waveformDrag(map: WarpMap, left: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(WaveformRow.space))
            .onChanged { value in
                if gesture == nil {
                    gesture = .click
                    selectedMarker = nil
                    if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                        let beat = Double(value.startLocation.x / beatWidth)
                        let marker = WarpMarker(sourceTime: map.sourceTime(atBeat: beat), beat: beat)
                        if session.sequence?.audio?.setMarker(marker) == true {
                            gesture = .newMarker(marker)
                            selectedMarker = marker.id
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

    /// Sixteenth notes, unless dragging freely.
    private func snap(_ beat: Double, free: Bool) -> Double {
        free ? beat : (beat * 4).rounded() / 4
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
private struct WarpFlag: View {
    let height: CGFloat
    let isActive: Bool
    var grabsWholeLine = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 11))
                .foregroundColor(isActive ? .orange : .yellow)
            Rectangle()
                .fill(isActive ? Color.orange : Color.yellow)
                .frame(width: isActive ? 2 : 1.5, height: height - 11)
        }
        .frame(width: 12, height: height)
        .contentShape(Rectangle().size(width: 12, height: grabsWholeLine ? height : 14))
    }
}
