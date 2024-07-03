//
//  LibraryItem.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import Foundation

class LibraryItem : Identifiable, Hashable {    
    var name: String
    var type: NoteCollectionMode
    var rating: Int = 0
    
    var chordType: ChordType? = nil
    var scaleType: ScaleType? = nil
    
    init(name: String, type: NoteCollectionMode, chordType: ChordType? = nil, scaleType: ScaleType? = nil) {
        self.name = name
        self.type = type
        
        self.chordType = chordType
        self.scaleType = scaleType
    }
    
    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        return lhs.name == rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
