//
//  Theme.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//
import SwiftUI
import Foundation

class Theme {
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
    
    let intervalColors: [Color] = [
        Color(hue: 0, saturation: 0.64, brightness: 0.00, opacity: 1.00),
        Color(hue: 0.08, saturation: 0.62, brightness: 0.98, opacity: 1.00),
        Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00),
        Color(hue: 0.04, saturation: 0.48, brightness: 0.95, opacity: 1.00),
        Color(hue: 0.10, saturation: 0.48, brightness: 0.95, opacity: 1.00),
        Color(hue: 0.14, saturation: 0.50, brightness: 0.95, opacity: 1.00),
        Color(hue: 0.29, saturation: 0.33, brightness: 0.86, opacity: 1.00),
        Color(hue: 0.62, saturation: 0.58, brightness: 0.86, opacity: 1.00),
        Color(hue: 0.74, saturation: 0.64, brightness: 0.65, opacity: 1.00),
        Color(hue: 0.85, saturation: 0.64, brightness: 0.65, opacity: 1.00),
        Color(hue: 0.92, saturation: 0.49, brightness: 0.93, opacity: 1.00),
        Color(hue: 0.975, saturation: 0.49, brightness: 0.93, opacity: 1.00)
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
