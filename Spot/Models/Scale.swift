//
//  Scale.swift
//  SongBook
//
//  Created by Brian on 28/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

public class Scale: CustomStringConvertible {
    
    var type: ScaleType = .Major
    
    init(_ type: ScaleType) {
        self.type = type
    }
    
    func notes(_ key: Note) -> [Note] {
        return NoteService.getNotes(type.intervals, key: key)
    }
    
    func chords(style: ChordStyle = .Triad) -> [ChordType] {
        return ChordService.getChordTypes(self.type)
    }
    
    public var description: String {
        return type.description
    }
}
