//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//
import SwiftUI
import SpotCore

struct FretboardView: View {
    @Environment(SelectionState.self) private var selection
    @Environment(DisplaySettings.self) private var display
    @Environment(\.theme) private var theme

    @State private var guitarOpacity: CGFloat = 0.3

    private var fretboard: Fretboard {
        selection.fretboard
    }

    let markerSize: CGFloat = 0.7 // TODO: Calculate this

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let fretSpacing = width / CGFloat(fretboard.fretCount + 1)
            let stringSpacing = height / CGFloat(fretboard.stringCount + 1)

            ZStack {
                drawFretMarkers(width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                    .opacity(guitarOpacity)
                drawFrets(width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                    .opacity(guitarOpacity)
                drawNut(width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                    .opacity(guitarOpacity)
                drawStrings(width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                    .opacity(guitarOpacity)
                drawFretNumbers(width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                    .opacity(guitarOpacity)
                drawMarkers(width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
            }
            .frame(maxWidth: .infinity)        }
            .frame(maxWidth: .infinity, maxHeight: 300)
            .padding(0)
    }

    /// Strings are numbered from the lowest, but drawn with the highest at the top like tab.
    private func y(forString string: Int, stringSpacing: CGFloat) -> CGFloat {
        CGFloat(fretboard.stringCount - string) * stringSpacing
    }

    func drawNut(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let nutWidth: CGFloat = fretSpacing

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: fretSpacing, y: stringSpacing - 1.0))
                path.addLine(to: CGPoint(x: fretSpacing, y: height - stringSpacing + 1.0))
            }
            .stroke(theme.fretColor, lineWidth: 4)

            Path { path in
                path.move(to: CGPoint(x: fretSpacing * 0.5, y: stringSpacing - 1.0))
                path.addLine(to: CGPoint(x: fretSpacing * 0.5, y: height - stringSpacing + 1.0))
            }
            .stroke(theme.nutColor, lineWidth: nutWidth)
        }
    }

    func drawFrets(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        ZStack {
            ForEach(1...fretboard.fretCount - 1, id: \.self) { fret in
                let isTwelthFret = fret % 12 == 11 || fret % 12 == 0
                let fretWidth: CGFloat = isTwelthFret ? 2 : 1

                Path { path in
                    let x = (CGFloat(fret) * fretSpacing) + fretSpacing
                    path.move(to: CGPoint(x: x, y: stringSpacing))
                    path.addLine(to: CGPoint(x: x, y: height - stringSpacing))
                }
                .stroke(theme.fretColor, style: StrokeStyle(lineWidth: fretWidth))
            }
        }
    }

    func drawStrings(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let exponent: CGFloat = 1.5
        let minStringWidth: CGFloat = 2.0
        let maxStringWidth: CGFloat = 2.0

        return ZStack {
            ForEach(1...fretboard.stringCount, id: \.self) { string in
                Path { path in
                    let y = CGFloat(string) * stringSpacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(theme.stringColor,
                        style: StrokeStyle(
                            lineWidth: calculateStringWidth(forString: string,
                                                            totalStrings: fretboard.stringCount,
                                                            minLineWidth: minStringWidth,
                                                            maxLineWidth: maxStringWidth,
                                                            exponent: exponent)
                        )
                )
            }
        }
    }

    func drawFretNumbers(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        ForEach(0...fretboard.fretCount, id: \.self) { fret in
            let x = (CGFloat(fret) * fretSpacing - fretSpacing / 2) + fretSpacing
            let y = (height - (stringSpacing / 4)) + 2

            Text(fret == 0 ? "0" : "\(fret)")
                .font(.caption.weight(.bold))
                .foregroundColor(theme.fretboardColor)
                .frame(width: fretSpacing, height: stringSpacing / 2, alignment: .top)
                .position(x: x, y: y)
        }
    }

    func drawFretMarkers(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let singleFretMarkers: [Int] = [3, 5, 7, 9, 15, 17, 19, 21] // TODO: Programatically derive this from the fret length
        let doubleFretMarkers: [Int] = [12, 24] // TODO: Programatically derive this from the fret length

        return ZStack {
            ForEach(singleFretMarkers, id: \.self) { fret in
                let x = (CGFloat(fret) * fretSpacing - fretSpacing / 2) + fretSpacing

                Circle()
                    .fill(theme.fretMarkerColor)
                    .frame(width: markerSize * min(fretSpacing, stringSpacing), height: markerSize * min(fretSpacing, stringSpacing))
                    .position(x: x, y: height / 2)
            }

            ForEach(doubleFretMarkers.indices, id: \.self) { index in
                let fret = doubleFretMarkers[index]
                let x = (CGFloat(fret) * fretSpacing - fretSpacing / 2) + fretSpacing

                VStack(spacing: stringSpacing) {
                    Circle()
                        .fill(theme.fretMarkerColor)
                        .frame(width: markerSize * min(fretSpacing, stringSpacing), height: markerSize * min(fretSpacing, stringSpacing))
                    Circle()
                        .fill(theme.fretMarkerColor)
                        .frame(width: markerSize * min(fretSpacing, stringSpacing), height: markerSize * min(fretSpacing, stringSpacing))
                }
                .position(x: x, y: height / 2)
            }
        }
    }

    func drawMarkers(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let size = min(fretSpacing, stringSpacing) * markerSize

        // While drawing a shape, show the draft and let clicks add or remove notes
        let isDrawing = selection.shapeDraft != nil
        let shape = isDrawing ? selection.draftPositions : selection.currentShape?.positions(root: selection.root, on: fretboard)
        
        let markers = FretMarker.build(fretboard: fretboard,
                                       root: selection.spelledRoot,
                                       formula: selection.formula,
                                       key: selection.key,
                                       shape: shape)
        
        return ForEach(markers) { marker in
            let isHighlighted = (display.highlightAllPositions && !isDrawing) || marker.isInPosition
            let isVisible = display.isolatePosition && !isDrawing
                ? isHighlighted
                : !display.hideUnrelatedNotes || marker.isInCollection
            
            FretMarkerView(marker: marker,
                           label: label(for: marker),
                           isHighlighted: isHighlighted,
                           size: size,
                           onSelect: {
                               if isDrawing {
                                   selection.toggleDraftNote(at: marker.position)
                               } else {
                                   selection.root = marker.pitchClass
                               }
                           },
                           onSetFinger: isDrawing && marker.isInPosition
                               ? { selection.setDraftFinger($0, at: marker.position) }
                               : nil)
                .position(x: (CGFloat(marker.position.fret) * fretSpacing - fretSpacing / 2) + fretSpacing,
                          y: y(forString: marker.position.string, stringSpacing: stringSpacing))
                .opacity(isVisible ? 1 : 0)
        }
    }

    private func label(for marker: FretMarker) -> String {
        switch display.markerLabel {
        case .interval: return marker.intervalName
        case .note: return marker.noteName.description
        case .finger: return marker.finger.map(String.init) ?? marker.intervalName
        }
    }

    private func calculateStringWidth(forString string: Int, totalStrings: Int, minLineWidth: CGFloat, maxLineWidth: CGFloat, exponent: CGFloat) -> CGFloat {
        let normalizedIndex = CGFloat(string - 1) / CGFloat(totalStrings - 1)
        let width = minLineWidth + (maxLineWidth - minLineWidth) * pow(normalizedIndex, exponent)
        return width
    }
}

private struct FretMarkerView: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    let marker: FretMarker
    let label: String
    let isHighlighted: Bool
    let size: CGFloat
    let onSelect: () -> Void
    /// Set while drawing a shape: right-click to choose a finger (nil = suggest).
    var onSetFinger: ((Int?) -> Void)? = nil

    var body: some View {
        let baseColor = marker.isOpenString ? theme.openMarkerColor : theme.defaultMarkerColor
        let markerColor = isHighlighted && marker.isInCollection
            ? theme.intervalColors[marker.semitonesAboveRoot]
            : baseColor
        let fillColor = marker.isInCollection ? Color.black : markerColor
        let scaledSize = size * (isHovered ? 1.1 : 1.0)

        // TODO: Adjust this so that the button wrapps the circle instead
        Circle()
            .stroke(lineWidth: 5)
            .fill(markerColor)
            .background(Circle().fill(fillColor))
            .frame(width: scaledSize, height: scaledSize)
            .overlay(
                Text(label)
                    .font(.caption)
                    .foregroundColor(marker.isInCollection || marker.isOpenString ? .white : theme.fretboardColor)
            )
            .onTapGesture(perform: onSelect)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .contextMenu {
                if let onSetFinger {
                    Button("Suggest finger") { onSetFinger(nil) }
                    Divider()
                    Button("Open string (0)") { onSetFinger(0) }
                    ForEach(1...4, id: \.self) { finger in
                        Button("Finger \(finger)") { onSetFinger(finger) }
                    }
                }
            }
    }
}
