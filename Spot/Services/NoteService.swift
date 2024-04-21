//
//  NoteUtility.swift
//  ArpGen
//
//  Created by Brian on 27/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

public class NoteService {
    class func getNotes(_ intervals: Interval..., key: Note) -> [Note] {
        return getNotes(intervals, key: key)
    }
    
    class func getNotes(_ intervals: [Interval], key: Note) -> [Note] {
        var output = [Note]()
        let indexOfRoot = key.rawValue
        
        for i in 0...intervals.count - 1 {
            let index = (indexOfRoot + intervals[i].rawValue) % Note.allCases.count
            let currentNote = Note(rawValue: index)!
            
            output.append(currentNote)
        }
        
        return output
    }
    
    class func getIntervals(_ notes: Note..., key: Note) -> [Interval] {
        return notes.map({ $0.interval(key: key) })
    }
    
    class func getNotesForTuning(tuning: [Note], frets: Int, root: Note, labelType: FretLabelType) -> [[FretNote]] {
        var output:[[FretNote]] = []
        
        for note in tuning {
            var stringNotes: [FretNote] = []
            let noteIndex = note.rawValue
            
            for fret in 0...frets {
                let currentFret = Note(rawValue: (fret + noteIndex) % 12)
                let fretNote = FretNote(note: currentFret!, labelType: labelType)
                stringNotes.append(fretNote)
            }
            
            output.append(stringNotes)
        }
        
        return output
    }
    
    class func getHighlightedNotesforScale(pattern: Int = 0,
                                           variation: Int = 0,
                                           tuning: [Note],
                                           scale: ScaleType,
                                           inversion: Inversion,
                                           selectedNote: Note) -> [[Int]] {
        let majorScalePatterns = MajorScaleThreeNotePerStringFrettingPatterns()
        
        var notes:[[Int]]  = []
    
        switch scale {
            case .Major:
                notes = majorScalePatterns.getPattern(pattern: inversion.rawValue, variation: variation)
            case .Dorian:
                notes = majorScalePatterns.getPattern(pattern: inversion.rawValue + 1 % 7, variation: variation)
            case .Phrygian:
                notes = majorScalePatterns.getPattern(pattern: inversion.rawValue + 2 % 7, variation: variation)
            case .Lydian:
                notes = majorScalePatterns.getPattern(pattern: inversion.rawValue + 3 % 7, variation: variation)
            case .Mixolydian:
                notes = majorScalePatterns.getPattern(pattern: inversion.rawValue + 4 % 7, variation: variation)
            case .Minor:
                notes = majorScalePatterns.getPattern(pattern: inversion.rawValue + 5 % 7, variation: variation)
            case .Locrian:
                notes = majorScalePatterns.getPattern(pattern: inversion.rawValue + 6 % 7, variation: variation)
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
            case .Blues:
                fallthrough
            default:
                return []
        }
        
        return transpose(notes, tuning: tuning, selectedNote: selectedNote)
    }
    
    private class func transpose(_ notes: [[Int]], tuning: [Note], selectedNote: Note) -> [[Int]] {
        guard let bassStringOpenNote = tuning.first else {
            return notes
        }
        
        let fretOffset = selectedNote.interval(key: bassStringOpenNote).rawValue

        let output = notes.map { string in
            string.map { fret in
                fret + fretOffset  // Add the offset directly
            }
        }
        
        return output
    }
}

