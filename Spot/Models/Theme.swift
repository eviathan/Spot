//
//  Theme.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//
import SwiftUI
import Foundation
import SpotCore

class Theme {
    /// An interval's colour on a dark background: the root (black on the fretboard) shown white.
    func chipColour(_ degree: SpotCore.Degree) -> Color {
        let semitones = ((degree.pitchClassOffset % 12) + 12) % 12
        return semitones == 0 ? .white : intervalColors[semitones]
    }

    /// An interval's colour by semitones above the root (any number: it's taken round the octave).
    func intervalColor(_ semitones: Int) -> Color {
        intervalColors[((semitones % 12) + 12) % 12]
    }

    /// Readable text on a solid interval colour: white on the root's black and the deep colours.
    func textColor(onInterval semitones: Int) -> Color {
        ((semitones % 12) + 12) % 12 == 0 || Theme.isDarkInterval(semitones) ? .white : .black
    }

    /// The interval colours dark enough to want white text on them (the deep blue of the ♭5).
    static func isDarkInterval(_ semitones: Int) -> Bool {
        ((semitones % 12) + 12) % 12 == 6
    }

    let fretboardColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    let stringColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.78, opacity: 1.00)
    let fretColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.38, opacity: 1.00)
    let fretMarkerColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.28, opacity: 0.20)
    let nutColor = Color(hue: 0.75, saturation: 0.01, brightness: 0.80, opacity: 1.00)
    
    /// Chord Practice colours by what a note does over the chord.
    let chordToneColor = Color(hue: 0.36, saturation: 0.55, brightness: 0.80, opacity: 1.00)
    let tensionColor = Color(hue: 0.57, saturation: 0.55, brightness: 0.92, opacity: 1.00)
    let avoidColor = Color(hue: 0.99, saturation: 0.65, brightness: 0.92, opacity: 1.00)
    
    let defaultMarkerColor: Color = Color(hue: 0.00, saturation: 0.00, brightness: 0.97, opacity: 1.00)
    let openMarkerColor: Color = Color(hue: 0.00, saturation: 0.00, brightness: 0.3, opacity: 1.00)
    
    /// One colour per interval (by semitones above the root), by what it does in a chord. The notes that make the
    /// chord get the primary colours, the colour tones and extensions the secondaries (softer, so they sit back);
    /// within each, the minor (or flattened) one deep and the major one bright. The root is black.
    /// - 3rds red, 5ths blue (the tritone as the ♭5, deep blue), 7ths yellow
    /// - 2nds/9ths orange, the 4th/11th green, 6ths/13ths purple
    /// All soft (pastel), in keeping with the rest of the app.
    let intervalColors: [Color] = [
        Color(hue: 0.000, saturation: 0.00, brightness: 0.00),   // R
        Color(hue: 0.060, saturation: 0.48, brightness: 0.80),   // m2 deep orange
        Color(hue: 0.075, saturation: 0.34, brightness: 1.00),   // M2 light orange
        Color(hue: 0.995, saturation: 0.62, brightness: 0.82),   // m3 deep red
        Color(hue: 0.005, saturation: 0.46, brightness: 1.00),   // M3 light red
        Color(hue: 0.360, saturation: 0.34, brightness: 0.82),   // P4 green
        Color(hue: 0.630, saturation: 0.48, brightness: 0.70),   // TT (♭5) deep blue
        Color(hue: 0.580, saturation: 0.48, brightness: 0.96),   // P5 blue
        Color(hue: 0.760, saturation: 0.36, brightness: 0.72),   // m6 deep purple
        Color(hue: 0.760, saturation: 0.22, brightness: 0.97),   // M6 light purple
        Color(hue: 0.115, saturation: 0.62, brightness: 0.86),   // m7 ochre
        Color(hue: 0.145, saturation: 0.52, brightness: 1.00),   // M7 yellow
    ]
    
//    let markerColours: [Color] = [
//        Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00), // Red
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00),
//        Color(hue: 0.74, saturation: 0.64, brightness: 0.00, opacity: 1.00)
//    ]
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
