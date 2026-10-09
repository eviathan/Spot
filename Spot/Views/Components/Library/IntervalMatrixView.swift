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
        return DiatonicChords.build(scale: source.scale.formula, size: useSevenths ? 4 : 3, chords: library.bundle.chords)
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
            VStack(spacing: 8) {
                HStack {
                    if let source = selection.chordSourceScale, selection.kind == .chord {
                        Button("← \(source.spelledRoot.description) \(source.scale.name)") {
                            selection.returnToScale()
                        }
                        .buttonStyle(.link)
                    }
                    
                    Picker("", selection: $useSevenths) {
                        Text("Triads").tag(false)
                        Text("Sevenths").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(chords, id: \.scaleDegree) { diatonic in
                        column(diatonic)
                    }
                }
            }
            .padding([.top], 8)
            .padding([.bottom], 12)
            .frame(maxWidth: .infinity)
            .foregroundColor(.black)
            .background(Color(hue: 1.00, saturation: 0.00, brightness: 0.93, opacity: 1.00))
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
                .lineLimit(1)
        }
        .frame(width: 56)
        .padding(.vertical, 4)
        .background(selection.isSelected(diatonic) ? Color.black.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { selection.select(diatonic) }
        .help(diatonic.chord.map { "Show " + chordRoot.description + " " + $0.name } ?? "")
    }
}
