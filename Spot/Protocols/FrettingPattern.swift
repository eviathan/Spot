//
//  FrettingPattern.swift
//  Spot
//
//  Created by Brian Williams on 20/04/2024.
//

import Foundation

protocol FrettingPattern {
    associatedtype TNoteCollection: NoteCollection
    
    var inversion: [TNoteCollection : [[[Int]]]] { get set }
    
    func getPattern(type: ScaleType, pattern: Int, variation: Int) -> [[Int]]
}
