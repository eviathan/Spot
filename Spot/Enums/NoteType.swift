//
//  Notetype.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import Foundation

public enum NoteType: Int, CaseIterable, CustomStringConvertible {
    case A = 0
    case Bb = 1
    case B = 2
    case C = 3
    case Db = 4
    case D = 5
    case Eb = 6
    case E = 7
    case F = 8
    case Gb = 9
    case G = 10
    case Ab = 11
    
    
    public var description: String {
        switch self {
            case .A: return "A"
            case .Bb: return "B♭"
            case .B: return "B"
            case .C: return "C"
            case .Db: return "D♭"
            case .D: return "D"
            case .Eb: return "E♭"
            case .E: return "E"
            case .F: return "F"
            case .Gb: return "G♭"
            case .G: return "G"
            case .Ab: return "A♭"
        }
    }
}

extension NoteType {
    func getMIDINumber(octave: Int = 0) -> Int {
        switch self {
        case .A:
            return 21 + (octave * 12)
        case .Ab:
            return 32 + (octave * 12)
        case .B:
            return 23 + (octave * 12)
        case .Bb:
            return 22 + (octave * 12)
        case .C:
            return 24 + (octave * 12)
        case .Db:
            return 25 + (octave * 12)
        case .D:
            return 26 + (octave * 12)
        case .Eb:
            return 27 + (octave * 12)
        case .E:
            return 28 + (octave * 12)
        case .F:
            return 29 + (octave * 12)
        case .Gb:
            return 30 + (octave * 12)
        case .G:
            return 31 + (octave * 12)
        }
    }
    
//    func interval(key: Note) -> Interval {
//        let indexOfRoot = key.rawValue
//        var count = 0
//        
//        for i in 0...Note.allCases.count {
//            let index = (indexOfRoot + i) % Note.allCases.count
//            let currentNote = Note(rawValue: index)
//            
//            if currentNote == self {
//                return Interval(rawValue: i)!
//            } else {
//               count+=1
//            }
//        }
//        
//        return .I
//    }
}
