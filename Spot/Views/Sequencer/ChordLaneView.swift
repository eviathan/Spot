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

    @State private var scrollOffset: CGFloat = 0

    /// Chords and sections, plus a waveform row when there's audio and a row of takes when there are any.
    private var laneHeight: CGFloat {
        takesTop + (sequence.takes.isEmpty ? 0 : takesHeight + 4) + 20
    }
    let waveformTop: CGFloat = 84
    let waveformHeight: CGFloat = 60
    let takesHeight: CGFloat = 22
    private var takesTop: CGFloat {
        sequence.audio == nil ? waveformTop : waveformTop + waveformHeight + 4
    }

    private var beatWidth: CGFloat {
        editor.barWidth / CGFloat(sequence.beatsPerBar)
    }

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id

        GeometryReader { geometry in
            let viewport = geometry.size.width
            if isPlaying {
                TimelineView(.animation) { _ in
                    let x = CGFloat(transport.position()) * beatWidth
                    let playheadX = viewport * 0.25
                    let left = x - playheadX
                    ZStack(alignment: .topLeading) {
                        lane(visible: left...(left + viewport))
                            .offset(x: -left)
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: laneHeight)
                            .offset(x: playheadX)
                    }
                    .frame(width: viewport, alignment: .leading)
                    .clipped()
                }
            } else {
                ScrollView(.horizontal) {
                    lane(visible: scrollOffset...(scrollOffset + viewport))
                        .background(GeometryReader { content in
                            Color.clear.preference(key: LaneScrollOffset.self, value: -content.frame(in: .named("lane")).minX)
                        })
                        .overlay(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.orange.opacity(0.8))
                                .frame(width: 2, height: laneHeight)
                                .offset(x: CGFloat(editor.pausedAt ?? editor.selection.start) * beatWidth)
                                .allowsHitTesting(false)
                        }
                }
                .coordinateSpace(name: "lane")
                .onPreferenceChange(LaneScrollOffset.self) { scrollOffset = max(0, $0) }
            }
        }
        .frame(height: laneHeight + 16)
    }

    private func lane(visible: ClosedRange<CGFloat>) -> some View {
        let width = CGFloat(sequence.lengthInBeats) * beatWidth
        let isPlaying = playback.playingSequence == editor.id

        return ZStack(alignment: .topLeading) {
            // Clicking the top part (sections, chords, bar numbers) selects bars
            Color.clear
                .frame(width: width, height: waveformTop)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    guard !isPlaying else { return }
                    editor.select(beat: Double(location.x / beatWidth),
                                  extend: NSEvent.modifierFlags.contains(.shift), in: sequence)
                }

            // Selection and loop
            if !isPlaying {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: CGFloat(editor.selection.length) * beatWidth, height: laneHeight)
                    .offset(x: CGFloat(editor.selection.start) * beatWidth)
                    .allowsHitTesting(false)
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

            // Chords
            ForEach(sequence.chords) { region in
                let parsed = editor.analysis.chords[region.id]
                VStack(alignment: .leading, spacing: 1) {
                    Text(parsed?.description ?? region.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    if let scale = editor.analysis.scales[region.id] {
                        Text(scale.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .opacity(0.6)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: max(0, CGFloat(region.range.length) * beatWidth - 2), height: 46, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(parsed == nil ? Color.red.opacity(0.4) : Color.blue.opacity(0.35)))
                .offset(x: CGFloat(region.range.start) * beatWidth + 1, y: 30)
                .allowsHitTesting(false)
            }

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
                WaveformRow(sequence: sequence, audio: audio, beatWidth: beatWidth, visible: visible, height: waveformHeight)
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
    }
}

private struct LaneScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    let audio: AudioTrack
    let beatWidth: CGFloat
    /// The part of the lane on screen, in lane x coordinates.
    let visible: ClosedRange<CGFloat>
    let height: CGFloat

    @Environment(SequenceSession.self) private var session

    /// A marker being dragged (an existing one, or a new one grabbed from the waveform).
    @State private var dragging: WarpMarker?
    @State private var hovered: UUID?

    /// The markers as they'd be with the drag applied, so the waveform follows the mouse.
    private var liveMarkers: [WarpMarker] {
        guard let dragging else { return audio.warpMarkers }
        return (audio.warpMarkers.filter { $0.id != dragging.id } + [dragging]).sorted { $0.beat < $1.beat }
    }

    var body: some View {
        let map = WarpMap(markers: liveMarkers, tempo: sequence.tempo)
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

                    // Beats heard by the analysis, where they land now (bar starts taller)
                    if let analysis = session.analysis, session.showsAnalysis {
                        var ticks = Path()
                        for (index, time) in analysis.beats.enumerated() {
                            let x = CGFloat(map.beat(atSourceTime: time)) * beatWidth - left
                            guard x >= 0, x <= size.width else { continue }
                            let isBarStart = (index - analysis.downbeat) % analysis.beatsPerBar == 0
                            ticks.move(to: CGPoint(x: x, y: size.height))
                            ticks.addLine(to: CGPoint(x: x, y: size.height * (isBarStart ? 0.35 : 0.7)))
                        }
                        context.stroke(ticks, with: .color(.teal), lineWidth: 1.5)
                    }
                }
                .frame(width: width, height: height)
                .offset(x: left)
                .contentShape(Rectangle())
                .gesture(waveformDrag(map: map, left: left))
                .simultaneousGesture(
                    SpatialTapGesture(count: 2).onEnded { tap in
                        // A new marker exactly where you clicked; nothing moves until you drag it
                        let beat = Double((left + tap.location.x) / beatWidth)
                        session.sequence?.audio?.setMarker(WarpMarker(sourceTime: map.sourceTime(atBeat: beat), beat: beat))
                    }
                )
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
                    WarpFlag(height: height, isActive: dragging?.id == marker.id || hovered == marker.id)
                        .offset(x: x - 6)
                        .onHover { hovered = $0 ? marker.id : (hovered == marker.id ? nil : hovered) }
                        .gesture(markerDrag(marker, map: map))
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            session.sequence?.audio?.removeMarker(marker.id)
                        })
                        .contextMenu {
                            Button("Delete Warp Marker") { session.sequence?.audio?.removeMarker(marker.id) }
                        }
                        .help("Drag to stretch onto a beat (⌥ free, ⇧ slide along the audio). Double-click to remove.")
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
                let flags = NSEvent.modifierFlags
                // The marker as it was before this drag (the one on screen has already moved)
                let original = audio.warpMarkers.first { $0.id == marker.id } ?? marker
                let grab = value.startLocation.x - CGFloat(original.beat) * beatWidth
                let raw = Double((value.location.x - grab) / beatWidth)
                var moved = original
                if flags.contains(.shift) {
                    let base = WarpMap(markers: audio.warpMarkers.filter { $0.id != marker.id }, tempo: sequence.tempo)
                    moved.beat = raw
                    moved.sourceTime = base.sourceTime(atBeat: raw)
                } else {
                    moved.beat = snap(raw, free: flags.contains(.option))
                }
                dragging = clamped(moved)
            }
            .onEnded { _ in commitDrag() }
    }

    /// Grab the audio at the click and pull that moment onto a beat (a new marker, made on the fly).
    private func waveformDrag(map: WarpMap, left: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(WaveformRow.space))
            .onChanged { value in
                // Where the drag began in the audio, worked out once with the map as it was then
                let existing = dragging ?? {
                    let startBeat = Double(value.startLocation.x / beatWidth)
                    return WarpMarker(sourceTime: map.sourceTime(atBeat: startBeat), beat: startBeat)
                }()
                var moved = existing
                moved.beat = snap(Double(value.location.x / beatWidth), free: NSEvent.modifierFlags.contains(.option))
                dragging = clamped(moved)
            }
            .onEnded { _ in commitDrag() }
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

private struct WarpFlag: View {
    let height: CGFloat
    let isActive: Bool

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
        .contentShape(Rectangle())
    }
}
