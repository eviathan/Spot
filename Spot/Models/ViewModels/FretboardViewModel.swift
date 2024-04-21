//
//  FretboardViewModel.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import Foundation
import SwiftUI

class FretboardViewModel: ObservableObject {
    let numberOfFrets: Int = 24
    let numberOfStrings: Int = 6
    var notes: [[FretNote]] = []
    let chord: ChordType = .Dom7
    let scale: ScaleType = .Major(.Ionian)
    let tuning: [Note] = [.E, .A, .D, .G, .B, .E]
    
    let appState: AppState
    
    // TODO: Take these from the theme on the AppState when themeing is done
    let fretboardColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    let stringColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.78, opacity: 1.00)
    let fretColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.28, opacity: 1.00)
    let fretMarkerColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.28, opacity: 0.20)
    
    // TODO: Deprecate this in favour of the below in order to facilitate themeing
    let markerColorA = Color(hue: 0.04, saturation: 0.48, brightness: 0.95, opacity: 1.00)
    let markerColorB = Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00)
    let markerColorC = Color(hue: 0.62, saturation: 0.58, brightness: 0.86, opacity: 1.00)
    
    let defaultMarkerColor: Color = Color(hue: 0.00, saturation: 0.00, brightness: 0.97, opacity: 1.00)
    let openMarkerColor: Color = Color(hue: 0.00, saturation: 0.00, brightness: 0.3, opacity: 1.00)
    
    // TODO: Get this off the theme
    let markerColours: [Color] = [
        Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00), // Red
        Color(hue: 0.14, saturation: 0.50, brightness: 0.95, opacity: 1.00), // Yellow
        Color(hue: 0.93, saturation: 0.49, brightness: 0.93, opacity: 1.00), // Pink
        Color(hue: 0.29, saturation: 0.33, brightness: 0.86, opacity: 1.00), // Green
        Color(hue: 0.74, saturation: 0.64, brightness: 0.65, opacity: 1.00), // Purple
        Color(hue: 0.04, saturation: 0.48, brightness: 0.95, opacity: 1.00), // Orange
        Color(hue: 0.62, saturation: 0.58, brightness: 0.86, opacity: 1.00), // Blue
    ]
    
    init(appState: AppState) {
        self.appState = appState
        notes = NoteService.getNotesForTuning(tuning: tuning.reversed(),
                                              frets: 24, root: appState.selectedNote)
    }
    
    func getHighlightedNotesforScale(pattern: Int = 0, variation: Int = 0) -> [[Int]] {
        let majorScalePatterns = MajorScaleThreeNotePerStringFrettingPatterns()
        
        var notes:[[Int]]  = []
    
        switch scale {
            case .Major(_):
                notes = majorScalePatterns.getPattern(pattern: appState.inversion.rawValue, variation: variation)
            case .Minor:
                fallthrough
            case .HarmonicMinor:
                fallthrough
            case .Locrian13:
                fallthrough
            case .IonianSharp5:
                fallthrough
            case .DorianSharp11:
                fallthrough
            case .PhrygianDominant:
                fallthrough
            case .LydianSharp2:
                fallthrough
            case .SuperLocrianbb7:
                fallthrough
            case .MelodicMinor:
                fallthrough
            case .Dorianb2:
                fallthrough
            case .LydianAugmented:
                fallthrough
            case .LydianDominant:
                fallthrough
            case .Mixolydianb6:
                fallthrough
            case .Aeolianb5:
                fallthrough
            case .AlteredScale:
                fallthrough
            case .MajorPentatonic:
                fallthrough
            case .MinorPentatonic:
                fallthrough
            case .Blues(_):
                fallthrough
            default:
                return []
        }
        
        return transpose(notes: notes)
    }
    
    func onNoteClicked(note: Note) {
        appState.selectedNote = note
    }
    
    private func transpose(notes: [[Int]]) -> [[Int]] {
        guard let bassStringOpenNote = tuning.first else {
            return notes
        }
        
        let fretOffset = appState.selectedNote.interval(key: bassStringOpenNote).rawValue

        let output = notes.map { string in
            string.map { fret in
                fret + fretOffset  // Add the offset directly
            }
        }
        
        return output
    }
}
