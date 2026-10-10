//
//  ChordLaneView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Sections, chords and bars on a timeline. While stopped it scrolls freely and clicks select;
/// while playing the lane moves past a playhead fixed a quarter of the way across.
struct ChordLaneView: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(SequenceSession.self) private var session
    
    let barWidth: CGFloat = 140
    /// Chords and sections, plus a waveform row when there's audio.
    private var laneHeight: CGFloat {
        sequence.audio == nil ? 104 : 160
    }
    let waveformTop: CGFloat = 84
    let waveformHeight: CGFloat = 52

    private var beatWidth: CGFloat {
        barWidth / CGFloat(sequence.beatsPerBar)
    }

    var body: some View {
        let isPlaying = playback.playingSequence == editor.id

        GeometryReader { geometry in
            if isPlaying {
                TimelineView(.animation) { _ in
                    let x = CGFloat(transport.position()) * beatWidth
                    let playheadX = geometry.size.width * 0.25
                    ZStack(alignment: .topLeading) {
                        lane
                            .offset(x: playheadX - x)
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2, height: laneHeight)
                            .offset(x: playheadX)
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                    .clipped()
                }
            } else {
                ScrollView(.horizontal) {
                    lane
                        .overlay(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.orange.opacity(0.8))
                                .frame(width: 2, height: laneHeight)
                                .offset(x: CGFloat(editor.selection.start) * beatWidth)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            editor.select(beat: Double(location.x / beatWidth),
                                          extend: NSEvent.modifierFlags.contains(.shift), in: sequence)
                        }
                }
            }
        }
        .frame(height: laneHeight + 16)
    }

    private var lane: some View {
        let width = CGFloat(sequence.lengthInBeats) * beatWidth

        return ZStack(alignment: .topLeading) {
            // Selection and loop
            if !(playback.playingSequence == editor.id) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: CGFloat(editor.selection.length) * beatWidth, height: laneHeight)
                    .offset(x: CGFloat(editor.selection.start) * beatWidth)
            }
            if let loop = sequence.loop {
                Rectangle()
                    .fill(Color.yellow.opacity(0.7))
                    .frame(width: CGFloat(loop.length) * beatWidth, height: 4)
                    .offset(x: CGFloat(loop.start) * beatWidth, y: 0)
            }

            // Sections
            ForEach(sequence.sections) { section in
                Text(section.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(width: CGFloat(section.range.length) * beatWidth - 2, height: 20, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.purple.opacity(0.45)))
                    .offset(x: CGFloat(section.range.start) * beatWidth + 1, y: 6)
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
                .frame(width: CGFloat(region.range.length) * beatWidth - 2, height: 46, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(parsed == nil ? Color.red.opacity(0.4) : Color.blue.opacity(0.35)))
                .offset(x: CGFloat(region.range.start) * beatWidth + 1, y: 30)
            }

            if let audio = sequence.audio {
                WaveformRow(sequence: sequence, audio: audio, beatWidth: beatWidth, width: width, height: waveformHeight)
                    .offset(y: waveformTop)
            }
            
            // Bar lines and numbers
            ForEach(0..<sequence.lengthInBars, id: \.self) { bar in
                let x = CGFloat(bar) * barWidth
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: laneHeight - 18)
                    .offset(x: x, y: 0)
                ForEach(1..<sequence.beatsPerBar, id: \.self) { beat in
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 52)
                        .offset(x: x + CGFloat(beat) * beatWidth, y: 30)
                }
                Text("\(bar + 1)")
                    .font(.caption2)
                    .opacity(0.6)
                    .offset(x: x + 4, y: laneHeight - 16)
            }
        }
        .frame(width: width, height: laneHeight, alignment: .topLeading)
    }
}

/// The recording drawn in beat time (so it lines up with the grid), with warp markers to drag.
/// Double-click a hit to drop a marker there, then drag the marker onto the beat it belongs on.
private struct WaveformRow: View {
    let sequence: ChordSequence
    let audio: AudioTrack
    let beatWidth: CGFloat
    let width: CGFloat
    let height: CGFloat
    
    @Environment(SequenceSession.self) private var session
    @State private var dragging: (id: UUID, beat: Double)?
    
    var body: some View {
        let map = audio.map(tempo: sequence.tempo)
        
        ZStack(alignment: .topLeading) {
            if let peaks = session.peaks {
                Canvas { context, size in
                    let middle = size.height / 2
                    var path = Path()
                    for x in stride(from: 0, to: size.width, by: 1) {
                        let start = map.sourceTime(atBeat: Double(x / beatWidth))
                        let end = map.sourceTime(atBeat: Double((x + 1) / beatWidth))
                        guard end > 0, start < audio.reference.duration else { continue }
                        let (low, high) = peaks.range(from: start, to: end)
                        path.move(to: CGPoint(x: x, y: middle - CGFloat(high) * middle))
                        path.addLine(to: CGPoint(x: x, y: middle - CGFloat(low) * middle + 0.5))
                    }
                    context.stroke(path, with: .color(.cyan.opacity(audio.isMuted ? 0.25 : 0.7)), lineWidth: 1)
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    // A marker where you clicked, not moving anything yet
                    let beat = Double(location.x / beatWidth)
                    session.sequence?.audio?.setMarker(WarpMarker(sourceTime: map.sourceTime(atBeat: beat), beat: beat))
                }
            } else {
                Text(statusText)
                    .font(.caption)
                    .opacity(0.6)
                    .frame(width: 400, height: height, alignment: .leading)
                    .padding(.leading, 8)
            }
            
            // Beats heard by the analysis, where they land on the grid now (bar starts taller)
            if let analysis = session.analysis, session.showsAnalysis {
                Canvas { context, size in
                    var path = Path()
                    for (index, time) in analysis.beats.enumerated() {
                        let x = CGFloat(map.beat(atSourceTime: time)) * beatWidth
                        guard x >= 0, x <= size.width else { continue }
                        let isBarStart = (index - analysis.downbeat) % analysis.beatsPerBar == 0
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x, y: size.height * (isBarStart ? 0.35 : 0.7)))
                    }
                    context.stroke(path, with: .color(.teal), lineWidth: 1.5)
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false)
            }
            
            ForEach(audio.warpMarkers) { marker in
                let beat = dragging?.id == marker.id ? dragging!.beat : marker.beat
                WarpFlag(height: height)
                    .offset(x: CGFloat(beat) * beatWidth - 5)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                // Snap to beats; hold ⌥ for anywhere
                                let raw = marker.beat + Double(value.translation.width / beatWidth)
                                let snapped = NSEvent.modifierFlags.contains(.option) ? raw : raw.rounded()
                                dragging = (marker.id, snapped)
                            }
                            .onEnded { _ in
                                if let dragging {
                                    var moved = marker
                                    moved.beat = dragging.beat
                                    session.sequence?.audio?.setMarker(moved)
                                }
                                dragging = nil
                            }
                    )
                    .contextMenu {
                        Button("Delete Warp Marker") { session.sequence?.audio?.removeMarker(marker.id) }
                    }
                    .help("Drag onto the beat this moment belongs on (⌥ for between beats). Right-click to delete.")
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
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
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundColor(.yellow)
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 1.5, height: height - 10)
        }
        .frame(width: 10, height: height)
        .contentShape(Rectangle())
    }
}
