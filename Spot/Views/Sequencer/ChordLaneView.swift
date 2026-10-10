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

    let barWidth: CGFloat = 140
    let laneHeight: CGFloat = 104

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
