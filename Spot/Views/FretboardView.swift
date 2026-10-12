//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//
import SwiftUI
import SpotCore

/// How one note is drawn. Each tab decides this for itself.
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
    /// A thin extra ring just outside the marker, e.g. for notes shared with the next chord.
    var halo: Color? = nil
    /// A dashed halo: a weaker link than a solid one (e.g. in the next scale but not the next chord).
    var haloDashed = false
    /// Below 1 to fade a note in or out.
    var opacity: Double = 1
    /// A root: drawn as a rounded square rather than a circle, so it's the first thing the eye finds.
    var isRoot = false
    /// The right half filled in this colour instead: a note that's in two things at once (now and next).
    var split: Color? = nil
    /// How thick the halo is.
    var haloWidth: CGFloat = 1.5
    /// The ring dashed: a note that isn't here yet (coming in with the next chord).
    var ringDashed = false
    /// A dark edge on the label, to read across two colours (a split marker).
    var textShadow = false
    /// Not in what's shown (unrelated notes, ⌘U): on the piano, just the label.
    var isPlain = false
    /// How much it's sounding now (0–1: a shape being heard): on the piano, the whole key washed with its colour.
    var sounding: Double = 0
    /// Ringed with a black middle (in the scale, not the chord): on the piano, a tint ringed in its colour.
    var isRinged = false

    var id: FretPosition {
        marker.position
    }
}

/// The one look for notes on every fretboard (Library, Sequence, Tab): each interval in its colour, chord tones solid,
/// other notes of the scale ringed in their colour with a black middle, the root a rounded square; notes away from
/// the hand's position the same, see-through.
extension FretboardMarker {
    enum Tone {
        /// In the chord (or a chord or interval picked in the Library): solid.
        case chord
        /// In the scale but not the chord (or a scale picked in the Library): ringed, black middle.
        case scale
    }

    enum Prominence {
        /// Where the hand is.
        case full
        /// In the position but not the grip itself.
        case soft
        /// Elsewhere on the neck (shape isolation off): the same look, see-through.
        case faint
    }

    init(_ marker: FretMarker, label: String, tone: Tone, semitones: Int, prominence: Prominence = .full,
         theme: Theme, isVisible: Bool = true, canSetFinger: Bool = false) {
        let colour = theme.intervalColor(semitones)
        let isRoot = ((semitones % 12) + 12) % 12 == 0
        let size: CGFloat
        let opacity: Double
        switch prominence {
        case .full: (size, opacity) = (1, 1)
        case .soft: (size, opacity) = (1, 0.8)
        case .faint: (size, opacity) = (1, 0.5)
        }
        switch tone {
        case .chord:
            self.init(marker: marker, label: label, ring: colour, fill: colour, text: theme.textColor(onInterval: semitones),
                      isVisible: isVisible, scale: size, canSetFinger: canSetFinger, opacity: opacity, isRoot: isRoot)
        case .scale:
            self.init(marker: marker, label: label, ring: colour, fill: .black, text: .white,
                      isVisible: isVisible, scale: size, canSetFinger: canSetFinger, opacity: opacity, isRoot: isRoot)
            isRinged = true
        }
    }

    /// A note outside what's shown (with unrelated notes on, ⌘U): plain.
    static func unrelated(_ marker: FretMarker, label: String, theme: Theme, isVisible: Bool) -> FretboardMarker {
        let ring = marker.position.fret == 0 ? theme.openMarkerColor : theme.defaultMarkerColor
        var plain = FretboardMarker(marker: marker, label: label, ring: ring, fill: ring,
                                    text: marker.position.fret == 0 ? .white : theme.fretboardColor,
                                    isVisible: isVisible, scale: 0.8)
        plain.isPlain = true
        return plain
    }
}

/// Draws the neck and a set of markers. What the markers mean is up to the caller.
/// With the piano chosen (DisplaySettings), the same markers on a keyboard instead.
struct FretboardView: View {
    @Environment(\.theme) private var theme
    @Environment(PlaybackController.self) private var playback
    @Environment(DisplaySettings.self) private var display
    @Environment(\.fretboardMaxHeight) private var maxHeight
    
    /// How strongly the neck (strings, frets, inlays) is drawn under the notes; the piano's key edges match it.
    static let neckOpacity: CGFloat = 0.3

    @State private var guitarOpacity: CGFloat = FretboardView.neckOpacity
    
    let fretboard: Fretboard
    let markers: [FretboardMarker]
    var onTap: (FretMarker) -> Void = { _ in }
    var onSetFinger: (FretMarker, Int?) -> Void = { _, _ in }
    
    let markerSize: CGFloat = 0.7 // TODO: Calculate this

    var body: some View {
        if display.instrument == .piano {
            PianoView(fretboard: fretboard, markers: markers, onTap: onTap)
        } else {
            neck
        }
    }

    private var neck: some View {
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
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
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
        
        let shape = MarkerShape(isRoot: item.isRoot)
        // TODO: Adjust this so that the button wrapps the circle instead
        shape
            .stroke(item.ring, style: StrokeStyle(lineWidth: (item.ringDashed ? 3 : 5) * item.scale,
                                                  dash: item.ringDashed ? [4 * item.scale, 3 * item.scale] : []))
            .overlay {
                if let halo = item.halo {
                    shape
                        .stroke(halo, style: StrokeStyle(lineWidth: item.haloWidth, dash: item.haloDashed ? [3, 2.5] : []))
                        .padding(-2 - item.haloWidth)
                }
            }
            .background {
                shape.fill(item.fill)
                if let split = item.split {
                    shape.fill(split)
                        .mask(alignment: .trailing) { Rectangle().frame(width: scaledSize / 2) }
                }
            }
            .frame(width: scaledSize, height: scaledSize)
            .overlay(
                // Longer labels (m13, ♭13) shrink to fit inside the ring; short ones stay as they are
                Text(item.label)
                    .font(.caption)
                    .foregroundColor(item.text)
                    .shadow(color: .black.opacity(item.textShadow ? 0.9 : 0), radius: 1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: max(1, scaledSize - 5 * item.scale - 3))
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

// MARK: - Piano

/// The fretboard's notes on a keyboard, across the guitar's range (whole octaves, from the C below the lowest open
/// string): a pad at the tip of each key that sounds one, in the fretboard markers' colours, with its label. Where one
/// pitch is on several frets, the key shows the most prominent of them (in the shape, being played), so a shape reads
/// as its exact notes.
/// - chord tones solid; the rest of the scale a tint ringed in its colour (as the fretboard rings them)
/// - the root: a fine line inside its pad
/// - being played: the whole key washed with the note's colour
/// - a ring round the pad: in the next chord too (half the pad in what it becomes there); dashed: new with it
/// - notes faint on the fretboard (away from the shape) faint here; unrelated ones (⌘U) just labelled
/// The keys go back under the panel above, the black ones in the theme's ink and set off-centre as on a piano.
/// Clicking a lit key does what clicking that fret does; ⌥-click plays any key.
struct PianoView: View {
    @Environment(\.theme) private var theme
    @Environment(PlaybackController.self) private var playback
    @Environment(\.fretboardMaxHeight) private var maxHeight
    @Environment(\.instrumentBase) private var base

    let fretboard: Fretboard
    let markers: [FretboardMarker]
    var onTap: (FretMarker) -> Void = { _ in }

    var body: some View {
        let notes = noteRange
        let whites = notes.filter { !PianoView.isBlack($0) }
        let byNote = markersByNote
        GeometryReader { geometry in
            let whiteWidth = geometry.size.width / CGFloat(max(whites.count, 1))
            let height = geometry.size.height
            let blackWidth = whiteWidth * 0.58
            let blackHeight = height * 0.62

            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.element) { index, note in
                    whiteKey(note, marker: byNote[note], width: whiteWidth, height: height)
                        .frame(width: whiteWidth, height: height)
                        .offset(x: CGFloat(index) * whiteWidth)
                }
                // Each black key over the line between its two white keys, nudged as on a piano
                ForEach(notes.filter(PianoView.isBlack), id: \.self) { note in
                    let whitesBelow = whites.filter { $0 < note }.count
                    blackKey(note, marker: byNote[note], width: blackWidth, height: blackHeight)
                        .frame(width: blackWidth, height: blackHeight)
                        .offset(x: CGFloat(whitesBelow) * whiteWidth - blackWidth / 2 + PianoView.nudge(note) * whiteWidth)
                }
                // The back of the keys goes under the panel above
                LinearGradient(colors: [theme.fretboardColor.opacity(0.16), theme.fretboardColor.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 10)
                    .allowsHitTesting(false)
            }
        }
        // Between the keys' rounded fronts: the view below, so they look to come down over it
        .background(alignment: .bottom) {
            ZStack {
                ForEach(base.indices, id: \.self) { base[$0] }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
    }

    private func whiteKey(_ note: Int, marker: FretboardMarker?, width: CGFloat, height: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
        let lit = marker.flatMap { $0.isPlain ? nil : $0 }
        return shape
            .fill(LinearGradient(colors: [Color(white: 0.985), Color(white: 0.955)], startPoint: .top, endPoint: .bottom))
            .overlay { if let lit, lit.sounding > 0 { shape.fill(lit.ring.opacity(0.32 * lit.sounding)) } }
            // Edged as the strings are drawn; open at the back, where the key goes under the panel
            .overlay { KeyEdge(radius: 6).stroke(theme.stringColor.opacity(FretboardView.neckOpacity), lineWidth: 1) }
            .overlay(alignment: .bottom) {
                if let marker {
                    pad(marker, onBlack: false, width: width - 6, height: min(44, height * 0.22))
                        .padding(.bottom, 4)
                } else if note == 60 {
                    // Middle C named, to find your way
                    Text("C4")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.fretboardColor.opacity(0.4))
                        .padding(.bottom, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { tapped(note, marker: marker) }
    }

    private func blackKey(_ note: Int, marker: FretboardMarker?, width: CGFloat, height: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
        let lit = marker.flatMap { $0.isPlain ? nil : $0 }
        return shape
            .fill(LinearGradient(colors: [theme.fretboardColor.opacity(0.92), theme.fretboardColor], startPoint: .top, endPoint: .bottom))
            .overlay { if let lit, lit.sounding > 0 { shape.fill(lit.ring.opacity(0.4 * lit.sounding)) } }
            // A lighter front edge, as a black key's sloped end catches the light
            .overlay(alignment: .bottom) { shape.fill(Color.white.opacity(0.08)).frame(height: 6) }
            .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1.5)
            .overlay(alignment: .bottom) {
                if let marker {
                    pad(marker, onBlack: true, width: width - 4, height: min(40, height * 0.26))
                        .padding(.bottom, 7)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { tapped(note, marker: marker) }
    }

    /// The note at a key's tip, as its fretboard marker shows it.
    private func pad(_ marker: FretboardMarker, onBlack: Bool, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let plainText = onBlack ? Color.white : theme.fretboardColor
        // A scale tone's marker is ringed with a black middle: here, a tint ringed in its colour
        let isTint = marker.isRinged
        return ZStack {
            if !marker.isPlain {
                if isTint {
                    shape.fill(marker.ring.opacity(onBlack ? 0.5 : 0.22))
                    shape.strokeBorder(marker.ring, lineWidth: 2)
                } else {
                    shape.fill(marker.fill)
                    if let split = marker.split {
                        // The right half: what it becomes in the next chord
                        shape.fill(split).mask { HStack(spacing: 0) { Color.clear; Color.black } }
                    }
                    if marker.ringDashed {
                        shape.strokeBorder(marker.ring, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                }
                if marker.isRoot {
                    shape.inset(by: 2.5).strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
                // In the next chord too (not being played: that washes the whole key)
                if let halo = marker.halo, marker.sounding == 0 {
                    shape.inset(by: -3).strokeBorder(halo, style: StrokeStyle(lineWidth: 2, dash: marker.haloDashed ? [3, 2.5] : []))
                }
            }
            Text(marker.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(marker.isPlain ? plainText.opacity(0.45) : (isTint ? plainText : marker.text))
                .shadow(color: .black.opacity(marker.textShadow ? 0.9 : 0), radius: 1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
        }
        .frame(width: max(1, width), height: height)
        .opacity(marker.isPlain ? 1 : marker.opacity)
    }

    private func tapped(_ note: Int, marker: FretboardMarker?) {
        // ⌥-click always plays the note
        if NSEvent.modifierFlags.contains(.option) {
            playback.previewNote(note)
        } else if let marker {
            onTap(marker.marker)
        }
    }

    /// Black keys sit off-centre, as on a piano: C♯ and D♯ apart, F♯ and A♯ out from G♯ (in white keys).
    private static func nudge(_ note: Int) -> CGFloat {
        switch ((note % 12) + 12) % 12 {
        case 1: return -0.08
        case 3: return 0.08
        case 6: return -0.1
        case 10: return 0.1
        default: return 0
        }
    }

    /// Whole octaves covering every note on the neck.
    private var noteRange: [Int] {
        let open = (0..<fretboard.stringCount).map { fretboard.midiNote(at: FretPosition(string: $0, fret: 0)) }
        let top = (0..<fretboard.stringCount).map { fretboard.midiNote(at: FretPosition(string: $0, fret: fretboard.fretCount)) }
        let low = open.min() ?? 40, high = top.max() ?? 88
        return Array((low - low % 12)...(high + 11 - high % 12))
    }

    /// For each pitch, the most prominent of its markers (the strongest look, then any extra ring).
    private var markersByNote: [Int: FretboardMarker] {
        var best: [Int: FretboardMarker] = [:]
        for marker in markers where marker.isVisible && marker.opacity > 0.01 {
            let note = fretboard.midiNote(at: marker.marker.position)
            if let current = best[note], PianoView.weight(current) >= PianoView.weight(marker) { continue }
            best[note] = marker
        }
        return best
    }

    private static func weight(_ marker: FretboardMarker) -> Double {
        marker.isPlain ? 0 : marker.opacity * Double(marker.scale) + (marker.halo != nil ? 0.5 : 0) + 0.01
    }

    static func isBlack(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((note % 12) + 12) % 12)
    }
}

/// A piano key's edge: down its sides and round its front, open at the back. Drawn half a point in, so a 1-point
/// line sits inside the key.
private struct KeyEdge: SwiftUI.Shape {
    var radius: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 0.5, dy: 0)
        let bottom = rect.maxY - 0.5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: bottom), control: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bottom - radius), control: CGPoint(x: rect.maxX, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// A marker's outline: a circle, or for a root a rounded square.
struct MarkerShape: SwiftUI.Shape {
    var isRoot: Bool

    func path(in rect: CGRect) -> Path {
        isRoot ? RoundedRectangle(cornerRadius: rect.width * 0.24, style: .continuous).path(in: rect)
               : Circle().path(in: rect)
    }
}

private struct FretboardMaxHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 300
}

private struct InstrumentBaseKey: EnvironmentKey {
    static let defaultValue: [Color] = []
}

extension EnvironmentValues {
    /// The view the instrument sits on (its colour, in layers from the bottom): the piano's keys come down over it,
    /// so it shows between their rounded fronts.
    var instrumentBase: [Color] {
        get { self[InstrumentBaseKey.self] }
        set { self[InstrumentBaseKey.self] = newValue }
    }

    /// How tall a fretboard may grow: taller when it has the window to itself.
    var fretboardMaxHeight: CGFloat {
        get { self[FretboardMaxHeightKey.self] }
        set { self[FretboardMaxHeightKey.self] = newValue }
    }
}
