//
//  IntervalMatrixView.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI
import SpotCore

/// The chords built on each degree of the selected scale. Clicking one selects it.
struct IntervalMatrixView: View {
    @Environment(\.theme) private var theme
    @Environment(SelectionState.self) private var selection
    @Environment(LibraryStore.self) private var library

    @State private var useSevenths = false
    @State var markerSize: CGFloat = 22;

    private var chords: [DiatonicChord] {
        guard let source = selection.chordSourceScale else { return [] }
        return DiatonicChords.build(scale: source.scale.formula, size: useSevenths ? 4 : 3, chords: library.chords)
    }

    func drawMarker(_ label: String, markerColor: Color) -> some View {
        return ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: markerSize, height: markerSize)
            Circle()
                .stroke(markerColor, lineWidth: 4)
                .frame(width: markerSize - 4, height: markerSize - 4)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white)
        }
    }

    var body: some View {
        let chords = self.chords

        if !chords.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SpotHeading("Chords in the scale")
                    Spacer()
                    if let source = selection.chordSourceScale, selection.kind == .chord {
                        Button("← \(source.spelledRoot.description) \(source.scale.name)") {
                            selection.returnToScale()
                        }
                        .buttonStyle(SpotPillButtonStyle())
                    }
                    Picker("", selection: $useSevenths) {
                        Text("Triads").tag(false)
                        Text("Sevenths").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 170)
                }

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(chords, id: \.scaleDegree) { diatonic in
                        column(diatonic)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func column(_ diatonic: DiatonicChord) -> some View {
        let chordRoot = (selection.chordSourceScale?.spelledRoot ?? selection.spelledRoot).spelling(diatonic.scaleDegree)

        return VStack(spacing: 3) {
            // Chord tones stacked in thirds, lowest at the bottom
            ForEach(diatonic.scaleDegrees.reversed(), id: \.self) { degree in
                drawMarker(degree.intervalName, markerColor: theme.intervalColors[degree.pitchClassOffset])
            }
            Text(diatonic.numeral)
                .font(.caption.weight(.bold))
                .padding(.top, 4)
            Text(diatonic.chord.map { chordRoot.description + $0.displaySymbol } ?? "–")
                .font(.caption2)
                .foregroundStyle(SpotStyle.secondary)
                .lineLimit(1)
        }
        .frame(width: 54)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selection.isSelected(diatonic) ? Color.white.opacity(0.10) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { selection.select(diatonic) }
        .help(diatonic.chord.map { "Show " + chordRoot.description + " " + $0.name } ?? "")
    }
}
