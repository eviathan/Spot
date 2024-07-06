//
//  LibraryItem.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import Foundation

class LibraryItem : ObservableObject, Identifiable, Hashable, Searchable {
    @Published var name: String
    @Published var type: NoteCollectionMode
    @Published var rating: Int = 0
    @Published var favourite: Bool = false
    
    @Published var chordType: ChordType? = nil
    @Published var scaleType: ScaleType? = nil
    @Published var interval: Interval? = nil
    
    var properties: [FuseProp] {
        [name].map{ FuseProp($0) }
    }
    
    init(name: String, type: NoteCollectionMode, chordType: ChordType? = nil, scaleType: ScaleType? = nil, interval: Interval? = nil) {
        self.name = name
        self.type = type
        
        self.chordType = chordType
        self.scaleType = scaleType
        self.interval = interval
    }
    
    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        return lhs.name == rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
