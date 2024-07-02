//
//  FretNote.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import Foundation

struct FretNote {
    var note: Note
    var labelType: FretLabelType
    
    func getLabel(_ type: FretLabelType?) -> String {
        let selectedType = type ?? labelType
        switch selectedType {
            case .interval(let note):
                return getInterval(rootNote: note).description
            case .note:
                return note.description
        }
    }
    
    func getInterval(rootNote: Note) -> Interval {
        let intervals = NoteService.getIntervals(note, key: rootNote)
        return intervals.first ?? .I
    }
}
