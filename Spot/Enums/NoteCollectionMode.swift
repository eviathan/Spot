//
//  NoteCollectionMode.swift
//  Spot
//
//  Created by Brian Williams on 21/04/2024.
//

import Foundation

enum NoteCollectionMode : CustomStringConvertible {
    case Scale
    case Chord
    
    public var description: String {
        switch self {
            case .Scale:
                return "Scales"
            case .Chord:
                return "Chords"
        }
    }
}
