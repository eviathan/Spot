//
//  MajorScaleFrettingPatterns.swift
//  Spot
//
//  Created by Brian Williams on 20/04/2024.
//

import Foundation

class MajorScaleThreeNotePerStringFrettingPatterns : FrettingPattern {
    var inversion: [ScaleType : [[[Int]]]]
    
    init() {
        self.inversion = [
            .Major(.Ionian) :
            [[
                [2,4,5],
                [2,4,5],
                [1,2,4],
                [1,2,4],
                [0,2,4],
                [0,2,4],
            ]],
            .Major(.Dorian) :
            [[
                [4,5,7],
                [4,5,7],
                [2,4,6],
                [2,4,6],
                [2,4,6],
                [2,4,5],
            ]],
        ]
    }
    
    func getPattern(type: ScaleType, pattern: Int, variation: Int = 0) -> [[Int]] {
        let variation = inversion[type]
        let pattern = variation![pattern]
        
        return pattern
    }
}
