//
//  NoteService.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import Foundation

func getNotesForTuning(tuning: [NoteType], frets: Int) -> [[FretNote]] {
    var output:[[FretNote]] = []
    
    for note in tuning {
        var stringNotes: [FretNote] = []
        let noteIndex = note.rawValue
        
        for fret in 0...frets {
            let currentFret = NoteType(rawValue: (fret + noteIndex) % 12)
            let fretNote = FretNote(note: currentFret!.description, type: currentFret!)
            stringNotes.append(fretNote)
        }
        
        output.append(stringNotes)
    }
    
    return output
}
