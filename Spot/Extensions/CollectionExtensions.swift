//
//  ArrayExtensions.swift
//  ArpGen
//
//  Created by Brian on 27/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

extension Collection where Element == Note {
    private func rotate(by rotations:Int) -> [Note]
    {
        let notes = self as! [Note]
        if rotations%notes.count <= 0 {
            return notes
        }
        
        var output = [Note]()
        
        var offset = rotations%notes.count
        if (rotations > notes.count) {
            offset = offset % notes.count
        }
        
        for i in offset...notes.count-1 {
            output.append(notes[i])
        }
        
        for i in 0...offset-1 {
            output.append(notes[i])
        }
        
        return output
    }
    
    func invert(_ inversion: Inversion) -> [Note] {
        return self.rotate(by: inversion.rawValue)
    }
}
