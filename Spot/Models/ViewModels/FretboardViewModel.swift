//
//  FretboardViewModel.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import Foundation
import SwiftUI

class FretboardViewModel {
    let numberOfFrets: Int = 24
    let numberOfStrings: Int = 6
    var notes: [[FretNote]] = []
    let chord: ChordType = .Dom7
    
    // TODO: Take these from the theme on the AppState when themeing is done
    let fretboardColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    let stringColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.28, opacity: 1.00)
    let markerColorA = Color(hue: 0.04, saturation: 0.48, brightness: 0.95, opacity: 1.00)
    let markerColorB = Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00)
    let markerColorC = Color(hue: 0.62, saturation: 0.58, brightness: 0.86, opacity: 1.00)
    
    init(appState: AppState) {
        notes = NoteService.getNotesForTuning(tuning: [.E, .A, .D, .G, .B, .E].reversed(),
                                              frets: 24, root: appState.selectedNote)
    }
}
