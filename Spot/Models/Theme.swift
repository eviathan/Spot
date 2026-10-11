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

    /// The interval colours dark enough to want white text on them (the deep minor 2nd, 6th and 7th).
    static func isDarkInterval(_ semitones: Int) -> Bool {
        [1, 8, 10].contains(((semitones % 12) + 12) % 12)
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
    
    /// One colour per interval (by semitones above the root), round the colour wheel in order of size, each pair
    /// a family with the minor one deep and the major one light: 2nds red, 3rds orange to gold, the 4th and 5th
    /// green and blue (the tritone a neutral slate between them), 6ths violet, 7ths magenta. The root is black.
    let intervalColors: [Color] = [
        Color(hue: 0.000, saturation: 0.00, brightness: 0.00),   // R
        Color(hue: 0.985, saturation: 0.78, brightness: 0.74),   // m2 crimson
        Color(hue: 0.020, saturation: 0.52, brightness: 0.99),   // M2 coral
        Color(hue: 0.065, saturation: 0.86, brightness: 0.90),   // m3 burnt orange
        Color(hue: 0.120, saturation: 0.72, brightness: 1.00),   // M3 gold
        Color(hue: 0.370, saturation: 0.58, brightness: 0.78),   // P4 green
        Color(hue: 0.600, saturation: 0.14, brightness: 0.62),   // TT slate
        Color(hue: 0.570, saturation: 0.72, brightness: 0.92),   // P5 blue
        Color(hue: 0.740, saturation: 0.62, brightness: 0.74),   // m6 violet
        Color(hue: 0.740, saturation: 0.32, brightness: 0.98),   // M6 lavender
        Color(hue: 0.860, saturation: 0.70, brightness: 0.74),   // m7 magenta
        Color(hue: 0.900, saturation: 0.34, brightness: 1.00),   // M7 pink
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
