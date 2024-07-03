//
//  Library.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import Foundation

class Library {
    var items: [LibraryItem] = []
    
    init() {
        items = getItems()
    }
    
    func getItems() -> [LibraryItem] {
        
        var output: [LibraryItem] = []
        
        for scale in ScaleType.allCases {
            let item = LibraryItem(name: scale.description, type: .Scale)
            item.scaleType = scale
            output.append(item)
        }
        
        for chord in ChordType.allCases {
            let item = LibraryItem(name: chord.description, type: .Chord)
            item.chordType = chord
            output.append(item)
        }
        
        return output
    }
}
