//
//  Appendix.swift
//  SongBook
//
//  Created by Brian on 29/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

public class Appendix {
    
    static let instance = Appendix()
    
    
    public var chordTypes: [[Interval]:ChordType] = [[Interval]:ChordType]()
    
    private init() {
        chordTypes = getChordDict()
    }
    
    private func getChordDict() -> [[Interval]:ChordType] {
        return ChordType.allCases.reduce(into: [[Interval]: ChordType]()) {
            $0[$1.intervals] = $1
        }
    }
}
