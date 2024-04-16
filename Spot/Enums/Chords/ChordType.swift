//
//  ChordType.swift
//  ArpGen
//
//  Created by Brian on 27/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

// TODO: Figure out how to deal with optional notes
public enum ChordType: String, CaseIterable, CustomStringConvertible {
    
    // Major
    case Maj = "M"
    case Add4 = "add4"
    case Sixth = "6"
    case SixNine = "6/9"
    case Maj7 = "Maj7"
    case Maj9 = "Maj9"
    case Maj11 = "Maj11"
    case Maj13 = "Maj13"
    case Maj7Sharp11 = "Maj7#11"
    case Majb5 = "Majb5"
    
    // Minor
    case Min = "m"
    case MinAdd4 = "madd4"
    case Min6 = "m6"
    case Min7 = "m7"
    case MinAdd9 = "madd9"
    case Min6Add9 = "m6/9"
    case Min9 = "m9"
    case Min11 = "m11"
    case Min13 = "m13"
    case MinMaj7 = "m/Maj7"
    case MinMaj9 = "m/Maj9"
    case MinMaj11 = "m/Maj11"
    case MinMaj13 = "m/Maj13"
    case Min7b5 = "ø"
    
    // Dominant
    case Dom7 = "7"
    case Dom9 = "9"
    case Dom11 = "11"
    case Dom13 = "13"
    case Dom7Sharp5 = "7#5"
    case Dom7b5 = "7b5"
    case Dom7Sharp9 = "7#9"
    case Dom7b9 = "7b9"
    case Dom9Sharp5 = "9#5"
    case Dom9b5 = "9b5"
    case Dom7Sharp5Sharp9 = "7#5#9"
    case Dom7Sharp5b9 = "7#5b9"
    case Dom7b5Sharp9 = "7b5#9"
    case Dom7b5b9 = "7b5b9"
    case Dom7Sharp11 = "7#11"
    
    // Symmetrical
    case Aug = "+"
    case Dim = "°"
    case Dim7 = "°7"
    
    // Misc
    case Fifth =  "5"
    case FlatFifth = "-5"
    case Sus4 = "sus4"
    case Sus2 = "sus2"
    case Sharp11 = "#11"
    
    public var description: String {
        return self.rawValue
    }
}

extension ChordType {
    var intervals: [Interval] {
        switch self {
            
        // Major
        case .Maj: return [.I, .III, .V]
        case .Add4: return [.I, .III, .IV, .V]
        case .Sixth: return [.I, .III, .V, .VI]
        case .SixNine: return [.I, .III, .V, .IX]
        case .Maj7: return [.I, .III, .V, .VII]
        case .Maj9: return [.I, .III, .V, .VII, .IX]
        case .Maj11: return [.I, .III, .V, .VII, .IX, .XI]
        case .Maj13: return [.I, .III, .V, .VI, .IX, .XI, .XIII]
        case .Maj7Sharp11: return [.I, .III, .V, .VII, .bXII]
        case .Majb5: return [.I, .III, .bV]
            
        // Minor
        case .Min: return [.I, .bIII, .V]
        case .MinAdd4: return [.I, .bIII, .IV, .V]
        case .Min6: return [.I, .bIII, .V, .VI]
        case .Min7: return [.I, .bIII, .V, .bVII]
        case .MinAdd9: return [.I, .bIII, .V, .IX]
        case .Min6Add9: return [.I, .bIII, .V, .VI, .IX]
        case .Min9: return [.I, .bIII, .V, .bVII, .IX]
        case .Min11: return [.I, .bIII, .V, .bVII, .IX, .XI]
        case .Min13: return [.I, .bIII, .V, .bVII, .IX, .XI, .XIII]
        case .MinMaj7: return [.I, .bIII, .V, .VII]
        case .MinMaj9: return [.I, .bIII, .V, .VII, .IX]
        case .MinMaj11: return [.I, .bIII, .V, .VII, .IX, .XI]
        case .MinMaj13: return [.I, .bIII, .V, .VII, .IX, .XI, .XIII]
        case .Min7b5: return [.I, .bIII, .bV, .bVII]
            
        // Dominant
        case .Dom7: return [.I, .III, .V, .bVII]
        case .Dom9: return [.I, .III, .V, .bVII, .IX]
        case .Dom11: return [.I, .III, .V, .bVII, .XI]
        case .Dom13: return [.I, .III, .V, .bVII, .IX, .XI, .XIII]
        case .Dom7Sharp5: return [.I, .III, .bVI, .bVII]
        case .Dom7b5: return [.I, .III, .bV, .bVII]
        case .Dom7Sharp9: return [.I, .III, .V, .bVII, .bIX]
        case .Dom7b9: return [.I, .III, .V, .bX]
        case .Dom9Sharp5: return [.I, .III, .bVI, .bVII, .IX]
        case .Dom9b5: return [.I, .III, .bV, .bVII, .IX]
        case .Dom7Sharp5Sharp9: return [.I, .III, .bVI, .bVII, .bX]
        case .Dom7Sharp5b9: return [.I, .III, .bVI, .bVII, .bIX]
        case .Dom7b5Sharp9: return [.I, .III, .bV, .bVII, .bX]
        case .Dom7b5b9: return [.I, .III, .bV, .bVII, .bIX]
        case .Dom7Sharp11: return [.I, .III, .V, .bVII, .bXII]
            
        // Symmetrical
        case .Aug: return [.I, .III, .bVI]
        case .Dim: return [.I, .bIII, .bVI]
        case .Dim7: return [.I, .bIII, .bVI, .bVII]
            
        // Misc
        case .Fifth: return [.I, .V]
        case .FlatFifth: return [.I, .bV]
        case .Sus4: return [.I, .IV, .V]
        case .Sus2: return [.I, .II, .V]
        case .Sharp11: return [.I, .V, .bXII]
        }
    }
    
    func getNotes(_ key: Note, inversion: Inversion = .Root) -> [Note] {
        return NoteService
            .getNotes(self.intervals, key: key)
                    .invert(inversion)
    }
}
