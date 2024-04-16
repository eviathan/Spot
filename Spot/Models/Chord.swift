//
//  Chords.swift
//  SongBook
//
//  Created by Brian on 28/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

public class Chord: Equatable {
    
    var key: Note
    var type: ChordType
    
    var notes: [Note] {
        get {
            return NoteService.getNotes(self.type.intervals, key: self.key)
        }
    }
    
    init(_ key: Note, _ type: ChordType){
        self.key = key
        self.type = type
    }
    
    public static func == (lhs: Chord, rhs: Chord) -> Bool {
        return lhs.type.intervals.elementsEqual(rhs.type.intervals)
    }
}
