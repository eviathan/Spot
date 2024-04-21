//
//  MajorScaleFrettingPatterns.swift
//  Spot
//
//  Created by Brian Williams on 20/04/2024.
//

import Foundation

class MajorScaleThreeNotePerStringFrettingPatterns : FrettingPattern {
    var patterns: [NoteGroup]
    
    init() {
        self.patterns = [
            NoteGroup("Ionian", notes: [
                [
                    [2, 4, 5],
                    [2, 4, 5],
                    [1, 2, 4],
                    [1, 2, 4],
                    [0, 2, 4],
                    [0, 2, 4],
                ]
            ]),
            NoteGroup("Dorian", notes: [
                [
                    [4, 5, 7],
                    [4, 5, 7],
                    [2, 4, 6],
                    [2, 4, 6],
                    [2, 4, 6],
                    [2, 4, 5],
                ]
            ]),
            NoteGroup("Phrygian", notes: [
                [
                    [5, 7, 9],
                    [5, 7, 9],
                    [4, 6, 8],
                    [4, 6, 7],
                    [4, 6, 7],
                    [4, 5, 7],
                ]
            ]),
            NoteGroup("Lydian", notes: [
                [
                    [7, 9, 11],
                    [7, 9, 10],
                    [6, 8, 9],
                    [6, 7, 9],
                    [6, 7, 9],
                    [5, 7, 9],
                ]
            ]),
            NoteGroup("Mixolydian", notes: [
                [
                    [9, 11, 12],
                    [9, 10, 12],
                    [8, 9, 11],
                    [7, 9, 11],
                    [7, 9, 11],
                    [7, 9, 11],
                ]
            ]),
            NoteGroup("Aeolian", notes: [
                [
                    [11, 12, 14],
                    [10, 12, 14],
                    [9, 11, 13],
                    [9, 11, 13],
                    [9, 11, 12],
                    [9, 11, 12],
                ]
            ]),
            NoteGroup("Locrian", notes: [
                [
                    [12, 14, 16],
                    [12, 14, 16],
                    [11, 13, 14],
                    [11, 13, 14],
                    [11, 12, 14],
                    [11, 12, 14],
                ]
            ]),
        ]
    }
    
    func getPattern(pattern: Int = 0, variation: Int = 0) -> [[Int]] {
        let selectedPattern = patterns[pattern]
        let selectedVariation: [[Int]] = selectedPattern.notes[variation]
        return selectedVariation
    }
}
