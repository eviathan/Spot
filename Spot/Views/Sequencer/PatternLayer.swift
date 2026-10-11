//
//  PatternLayer.swift
//  Spot
//

import SwiftUI
import AppKit
import SpotCore

/// The Patterns row, like looped clips in Live: each place a pattern is used, as a bar with its name, a faint
/// tint down over its chords, and a line where each repeat begins.
/// - click it to select it (⌘D, ⇧⌘G and the bar's Pattern menu act on it); double-click to rename it
/// - drag it to move it; drag its end to repeat it (or cut it short), its start to start part way in
/// - right-click: Rename, Duplicate, Make Unique, Ungroup, Delete (or select it and press Delete)
/// Edges and moves go by the grid (⌥ for free).
struct PatternLayer: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState
    let beatWidth: CGFloat
    let visible: ClosedRange<CGFloat>
    let isEditable: Bool
    /// The bars to grab (drawn over the chords, whose row catches clicks between them), or the tint and repeat
    /// lines (drawn under the chords).
    let showsBars: Bool

    @Environment(SequenceSession.self) private var session

    private enum Part { case body, start, end }
    /// An instance being dragged: where it would go, and where it would start in its pattern.
    @State private var drag: (id: UUID, range: BeatRange, phase: Double)?

    private static let barTop: CGFloat = 6
    private static let barHeight: CGFloat = 20
    /// The chord row, below (tinted over the pattern's stretch).
    private static let chordTop: CGFloat = 30
    private static let chordHeight: CGFloat = 46

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(sequence.instances) { instance in
                if let pattern = sequence.pattern(instance.patternId) {
                    let dragged = drag?.id == instance.id ? drag : nil
                    let range = dragged?.range ?? instance.range
                    let phase = dragged?.phase ?? instance.phase
                    // The one being dragged is always drawn (a view removed mid-drag never hears it end)
                    if let span = LaneSpan(range.start, range.end, beatWidth: beatWidth,
                                           visible: dragged != nil ? -CGFloat.infinity...CGFloat.infinity : visible) {
                        instanceView(instance, pattern: pattern, range: range, phase: phase, span: span, isDragged: dragged != nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func instanceView(_ instance: PatternInstance, pattern: ChordPattern, range: BeatRange, phase: Double,
                              span: LaneSpan, isDragged: Bool) -> some View {
        let uses = sequence.uses(of: pattern.id)
        let rounds = Int(ceil((range.length + phase) / pattern.length - 1e-9))
        let isSelected = editor.selection == instance.range
        let purple = Color(red: 0.62, green: 0.45, blue: 0.95)

        if !showsBars {
            tint(range: range, phase: phase, span: span, pattern: pattern, purple: purple)
        } else {
            bar(instance, pattern: pattern, range: range, span: span, uses: uses, rounds: rounds,
                isSelected: isSelected, isDragged: isDragged, purple: purple)
        }
    }

    /// Over the chords: a faint tint, and a line where each repeat starts (plain shapes, drawn whatever the zoom).
    @ViewBuilder
    private func tint(range: BeatRange, phase: Double, span: LaneSpan, pattern: ChordPattern, purple: Color) -> some View {
        Rectangle()
            .fill(purple.opacity(0.09))
            .frame(width: span.width, height: PatternLayer.chordHeight)
            .offset(x: span.x, y: PatternLayer.chordTop)
            .allowsHitTesting(false)
        ForEach(repeatStarts(range: range, phase: phase, length: pattern.length), id: \.self) { beat in
            Rectangle()
                .fill(purple.opacity(0.7))
                .frame(width: 1, height: PatternLayer.chordTop + PatternLayer.chordHeight - PatternLayer.barTop)
                .offset(x: CGFloat(beat) * beatWidth, y: PatternLayer.barTop)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func bar(_ instance: PatternInstance, pattern: ChordPattern, range: BeatRange, span: LaneSpan, uses: Int,
                     rounds: Int, isSelected: Bool, isDragged: Bool, purple: Color) -> some View {
        // The bar: drag to move, click to select, double-click to rename
        RoundedRectangle(cornerRadius: 3)
            .fill(purple.opacity(isDragged ? 0.75 : isSelected ? 0.65 : 0.45))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(isSelected ? 0.5 : 0)))
            .frame(width: max(0, span.width - 2), height: PatternLayer.barHeight)
            .offset(x: span.x + 1, y: PatternLayer.barTop)
            .gesture(dragGesture(instance, pattern: pattern, part: .body), including: isEditable ? .all : .none)
            .onTapGesture {
                // (The click count rather than a double-tap gesture, which would hold up single clicks)
                if NSApp.currentEvent?.clickCount == 2 {
                    editor.renamingPattern = pattern.id
                } else {
                    editor.select(instance.range, extend: false, in: sequence)
                }
            }
            .contextMenu {
                Button("Rename…") { editor.renamingPattern = pattern.id }
                Button("Duplicate") {
                    editor.select(instance.range, extend: false, in: sequence)
                    session.duplicatePattern()
                }
                Button("Make Unique") {
                    editor.select(instance.range, extend: false, in: sequence)
                    session.makePatternUnique()
                }
                .disabled(uses < 2)
                Divider()
                Button("Ungroup") {
                    editor.select(instance.range, extend: false, in: sequence)
                    session.ungroupPattern()
                }
                Button("Delete", role: .destructive) {
                    editor.select(instance.range, extend: false, in: sequence)
                    session.deletePattern()
                }
            }
            .help("\(pattern.name.isEmpty ? "A pattern" : pattern.name)\(uses > 1 ? ", used \(uses) times (linked: change one, change all)" : ""). Drag to move it, drag its end to repeat it; double-click to rename.")

        HStack(spacing: 6) {
            Image(systemName: uses > 1 ? "link" : "repeat")
                .font(.system(size: 9, weight: .bold))
            Text(pattern.name.isEmpty ? "Pattern" : pattern.name)
                .font(.caption.weight(.semibold))
                .opacity(pattern.name.isEmpty ? 0.6 : 1)
            if rounds > 1 {
                Text("×\(rounds)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .opacity(0.7)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(width: max(0, span.width - 2), height: PatternLayer.barHeight, alignment: .leading)
        .clipped()
        .offset(x: span.x + 1, y: PatternLayer.barTop)
        .allowsHitTesting(false)

        // The ends, to drag (not where the real end is off screen)
        if !span.startCut {
            edgeHandle(instance, pattern: pattern, part: .start)
                .offset(x: span.x, y: PatternLayer.barTop)
        }
        if !span.endCut {
            edgeHandle(instance, pattern: pattern, part: .end)
                .offset(x: span.x + span.width - 7, y: PatternLayer.barTop)
        }
    }

    private func edgeHandle(_ instance: PatternInstance, pattern: ChordPattern, part: Part) -> some View {
        Color.clear
            .frame(width: 7, height: PatternLayer.barHeight)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(dragGesture(instance, pattern: pattern, part: part), including: isEditable ? .all : .none)
            .help(part == .end ? "Drag to repeat the pattern (or cut it short)" : "Drag to start part way into the pattern")
    }

    /// Where each repeat after the first begins.
    private func repeatStarts(range: BeatRange, phase: Double, length: Double) -> [Double] {
        guard length > 0 else { return [] }
        var starts: [Double] = []
        var beat = range.start - phase + length
        while beat < range.end - 1e-9 && starts.count < 2000 {
            if beat > range.start + 1e-9 { starts.append(beat) }
            beat += length
        }
        return starts
    }

    private func dragGesture(_ instance: PatternInstance, pattern: ChordPattern, part: Part) -> some Gesture {
        // Measured in the lane's own coordinates: the bar and its ends move as they're dragged, so measured
        // against themselves the drag would come up short
        DragGesture(minimumDistance: 2, coordinateSpace: .named(ChordLaneView.contentSpace))
            .onChanged { value in
                let free = NSEvent.modifierFlags.contains(.option) || editor.snap == 0
                let snap = { (beat: Double) in free ? beat : sequence.onGrid(beat, unit: editor.snap, .toNearestOrAwayFromZero) }
                let delta = Double(value.translation.width / beatWidth)
                let shortest = max(free ? 0.0625 : editor.snap, 0.0625)
                var range = instance.range
                var phase = instance.phase
                switch part {
                case .body:
                    let start = max(0, snap(instance.range.start + delta))
                    range = BeatRange(start, start + instance.range.length)
                case .end:
                    range.end = min(max(snap(instance.range.end + delta), range.start + shortest), sequence.lengthInBeats)
                case .start:
                    let start = min(max(0, snap(instance.range.start + delta)), range.end - shortest)
                    phase = (instance.phase + start - instance.range.start).truncatingRemainder(dividingBy: pattern.length)
                    if phase < 0 { phase += pattern.length }
                    range.start = start
                }
                drag = (instance.id, range, phase)
            }
            .onEnded { _ in
                if let drag {
                    session.sequence?.setRange(of: drag.id, to: drag.range, moving: part == .body)
                    if let sequence = session.sequence, let moved = sequence.instances.first(where: { $0.id == drag.id }) {
                        editor.select(moved.range, extend: false, in: sequence)
                    }
                }
                drag = nil
            }
    }
}
