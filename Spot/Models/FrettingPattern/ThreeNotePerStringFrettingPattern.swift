//
//  MajorScaleFrettingPatterns.swift
//  Spot
//
//  Created by Brian Williams on 20/04/2024.
//

import Foundation

// TODO: Make this procedural
// Each string just gets three note parts of the scale in ascending pitch sequentially i.e. (1,2,3) then (4,5,6) etc
// Each Note group just augments the pattern by 1
class ThreeNotePerStringFrettingPattern : FrettingPattern {
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
    
    
    func getPatterns(_ scale: ScaleType,
                     pattern: Int = 0,
                     variation: Int = 0,
                     key: Note,
                     tuning: [Note],
                     fretRange: Int,
                     names: [String] = []) -> [[Int]] {
        
        var patterns: [[Int]] = []
        
        // Assume getNotes returns an array of Notes in the scale from the root
        let scaleNotes = scale.getNotes(key)
        
        // Iterate over each string based on the tuning
        for stringNote in tuning {
            var stringFrets: [Int] = []
            
            // Check each fret up to the fretRange to see if it matches any note in the scale
            for fret in 0...fretRange {
                let noteAtFret = Note(rawValue: (stringNote.rawValue + fret) % 12)
                if scaleNotes.contains(noteAtFret!) {
                    stringFrets.append(fret)
                    // Collect only the first three notes that can be played on this string
                    if stringFrets.count == 3 {
                        break
                    }
                }
            }
            
            // Append only if there are at least three notes; otherwise, consider the next string
            if stringFrets.count >= 3 {
                patterns.append(stringFrets)
            }
        }
        
        return patterns
    }

}
