//
//  FretboardViewModel.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import Foundation

class FretboardViewModel {
    var notes: [[FretNote]] = []
    let chord: ChordType = .Dom7
    
    init() {
        notes = NoteService.getNotesForTuning(tuning: [.E, .A, .D, .G, .B, .E].reversed(),
                                              frets: 22)
    }
}
