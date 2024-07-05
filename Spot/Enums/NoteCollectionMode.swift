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
    case Interval
    
    public var description: String {
        switch self {
            case .Scale:
                return "Scale"
            case .Chord:
                return "Chord"
            case .Interval:
                return "Interval"
        }
    }
}
