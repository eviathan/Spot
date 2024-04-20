//
//  FretNote.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import Foundation

struct FretNote {
    var type: Note
    var labelType: FretLabelType
    
    func getLabel() -> String {
        switch labelType {
            case .interval(let note):
                return getInterval(rootNote: note).description
            case .note:
                fallthrough
            default:
                return type.description
        }
    }
    
    func getInterval(rootNote: Note) -> Interval {
        let intervals = NoteService.getIntervals(type, key: rootNote)
        return intervals.first ?? .I
    }
}
