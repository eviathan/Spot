//
//  ChordService.swift
//  SongBook
//
//  Created by Brian on 29/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

// TODO: IMPLEMENT THESE
public class ChordService {
    
    // Chord Type
    class func getChordType(_ intervals: [Interval]) -> ChordType {
        return Appendix.instance.chordTypes[intervals] ?? .Maj
    }
    
    class func getChordType(_ intervals: Interval...) -> ChordType {
        return getChordType(intervals)
    }
    
    class func getChordTypes(_ scaleType: ScaleType) -> [ChordType] {
        //        let notes = scale.getNotes()
        
        return [ChordType]()
    }
    
    // Chord
    class func getChords(_ notes: [Note]) -> [Chord] {
        return [Chord]()
    }
    
    class func getChords(_ notes: Note...) -> [Chord] {
        return getChords(notes)
    }
}
