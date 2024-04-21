//
//  FrettingPattern.swift
//  Spot
//
//  Created by Brian Williams on 20/04/2024.
//

import Foundation

protocol FrettingPattern {
    var patterns: [NoteGroup] { get set }
    
    func getPattern(pattern: Int, variation: Int) -> [[Int]]
}

class NoteGroup {
    var name: String
    var notes: [[[Int]]]
    
    init(_ name: String = "", notes: [[[Int]]]) {
        self.name = name
        self.notes = notes
    }
}
