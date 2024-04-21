//
//  NoteCollectionMode.swift
//  Spot
//
//  Created by Brian Williams on 21/04/2024.
//

import Foundation

enum NoteCollectionMode : CustomStringConvertible {
    case Scales
    case Chords
    
    public var description: String {
        switch self {
            case .Scales:
                return "Scales"
            case .Chords:
                return "Chords"
        }
    }
}
