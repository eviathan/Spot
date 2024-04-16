//
//  ScaleDegreeType.swift
//  ArpGen
//
//  Created by Brian on 27/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

public enum Interval: Int, CustomStringConvertible {
    case I = 0
    case bII = 1
    case II = 2
    case bIII = 3
    case III = 4
    case IV = 5
    case bV = 6
    case V = 7
    case bVI = 8
    case VI = 9
    case bVII = 10
    case VII = 11
    
    // SECOND OCTAVE
    // NOTE: Commented out notes are for reference and not used
//    case VIII = 12
    case bIX = 13
    case IX = 14
    case bX = 15
//    case X = 16
    case XI = 17
    case bXII = 18
//    case XII = 19
    case bXIII = 20
    case XIII = 21
//    case bXIV = 22
//    case XIV = 23
    
    public var noteIndex: Int {
        switch self {
        case .I: return 0
        case .bII, .bIX: return 1
        case .II, .IX: return 2
        case .bIII, .bX: return 3
        case .III: return 4
        case .IV, .XI: return 5
        case .bV, .bXII: return 6
        case .V: return 7
        case .bVI, .bXIII: return 8
        case .VI, .XIII: return 9
        case .bVII: return 10
        case .VII: return 11
        }
    }
    
    public var description: String {
        switch self {
        case .I: return "R"
        case .bII: return "b2"
        case .II: return "2"
        case .bIII: return "b3"
        case .III: return "3"
        case .IV: return "4"
        case .bV: return "b5"
        case .V: return "5"
        case .bVI: return "b6"
        case .VI: return "6"
        case .bVII: return "b7"
        case .VII: return "7"
        case .bIX: return "b9"
        case .IX: return "9"
        case .bX: return "9#"
        case .XI: return "11"
        case .bXII: return "11#"
        case .bXIII: return "b13"
        case .XIII: return "13"
        }
    }
}
