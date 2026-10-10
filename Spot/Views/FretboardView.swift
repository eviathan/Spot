//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//
import SwiftUI
import SpotCore

/// How one note is drawn. The Library and Chord Practice tabs each decide this for themselves.
struct FretboardMarker: Identifiable {
    var marker: FretMarker
    var label: String
    var ring: Color
    var fill: Color
    var text: Color
    var isVisible = true
    /// 1 is full size; smaller for notes in the background.
    var scale: CGFloat = 1
    /// Right-click offers finger numbers (while drawing a shape).
    var canSetFinger = false
    /// An extra ring outside the marker, e.g. for notes shared with the next chord.
    var halo: Color? = nil
    /// Below 1 to fade a note in or out.
    var opacity: Double = 1
    /// A small label tucked against the top-right of the note, kept apart from the marker itself,
    /// e.g. what the note is in the next chord.
    var tag: FretTag? = nil

    var id: FretPosition {
        marker.position
    }
}

struct FretTag {
    var label: String
    var color: Color
    /// 0...1: how strongly it shows.
    var emphasis: Double = 1
    /// Drawn a little bigger (e.g. a note worth aiming for).
    var isStrong = false
}

/// Draws the neck and a set of markers. What the markers mean is up to the caller.
struct FretboardView: View {
    @Environment(\.theme) private var theme
    @Environment(PlaybackController.self) private var playback
    
    @State private var guitarOpacity: CGFloat = 0.3
    
    let fretboard: Fretboard
    let markers: [FretboardMarker]
    var onTap: (FretMarker) -> Void = { _ in }
    var onSetFinger: (FretMarker, Int?) -> Void = { _, _ in }
    
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
                drawTags(fretSpacing: fretSpacing, stringSpacing: stringSpacing)
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

    /// Tags sit up and to the right of their note, between the strings, so they never cover a marker.
    func drawTags(fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let size = min(fretSpacing, stringSpacing) * markerSize
        return ForEach(markers.filter { $0.tag != nil }) { item in
            let tag = item.tag!
            Text(tag.label)
                .font(.system(size: max(8, size * (tag.isStrong ? 0.42 : 0.36)), weight: tag.isStrong ? .heavy : .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Capsule().fill(tag.color))
                .overlay(Capsule().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                .fixedSize()
                .position(x: (CGFloat(item.marker.position.fret) * fretSpacing - fretSpacing / 2) + fretSpacing + size * 0.62,
                          y: y(forString: item.marker.position.string, stringSpacing: stringSpacing) - stringSpacing * 0.42)
                .opacity(0.45 + 0.55 * tag.emphasis)
                .allowsHitTesting(false)
        }
    }

    func drawMarkers(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let size = min(fretSpacing, stringSpacing) * markerSize
        
        return ForEach(markers) { item in
            FretMarkerView(item: item,
                           size: size,
                           onSelect: {
                               // ⌥-click always plays the note
                               if NSEvent.modifierFlags.contains(.option) {
                                   playback.previewNote(fretboard.midiNote(at: item.marker.position))
                               } else {
                                   onTap(item.marker)
                               }
                           },
                           onSetFinger: item.canSetFinger ? { onSetFinger(item.marker, $0) } : nil)
                .position(x: (CGFloat(item.marker.position.fret) * fretSpacing - fretSpacing / 2) + fretSpacing,
                          y: y(forString: item.marker.position.string, stringSpacing: stringSpacing))
                .opacity(item.isVisible ? item.opacity : 0)
                .allowsHitTesting(item.isVisible)
        }
    }
    
    private func calculateStringWidth(forString string: Int, totalStrings: Int, minLineWidth: CGFloat, maxLineWidth: CGFloat, exponent: CGFloat) -> CGFloat {
        let normalizedIndex = CGFloat(string - 1) / CGFloat(totalStrings - 1)
        let width = minLineWidth + (maxLineWidth - minLineWidth) * pow(normalizedIndex, exponent)
        return width
    }
}

private struct FretMarkerView: View {
    @State private var isHovered = false
    
    let item: FretboardMarker
    let size: CGFloat
    let onSelect: () -> Void
    /// Set while drawing a shape: right-click to choose a finger (nil = suggest).
    var onSetFinger: ((Int?) -> Void)? = nil
    
    var body: some View {
        let scaledSize = size * item.scale * (isHovered ? 1.1 : 1.0)
        
        // TODO: Adjust this so that the button wrapps the circle instead
        Circle()
            .stroke(lineWidth: 5 * item.scale)
            .fill(item.ring)
            .overlay {
                if let halo = item.halo {
                    Circle()
                        .stroke(halo, lineWidth: 2)
                        .padding(-5)
                }
            }
            .background(Circle().fill(item.fill))
            .frame(width: scaledSize, height: scaledSize)
            .overlay(
                Text(item.label)
                    .font(.caption)
                    .foregroundColor(item.text)
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
