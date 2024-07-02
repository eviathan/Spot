//
//  LibraryItem.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import Foundation

class LibraryItem : Identifiable, Hashable {    
    var name: String
    
    init(name: String) {
        self.name = name
    }
    
    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        return lhs.name == rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
