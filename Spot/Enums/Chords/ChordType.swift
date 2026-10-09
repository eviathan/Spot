//
//  ChordType.swift
//  ArpGen
//
//  Created by Brian on 27/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

// TODO: Replace with SpotCore.ChordDefinition (optional notes now live there)
public enum ChordType: String, CaseIterable, CustomStringConvertible, Hashable, NoteCollection {
    
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
    
    /// The matching definition in SpotCore's built-in library, which now holds the formulas
    var definitionId: String {
        switch self {
        case .Maj: return "builtin.chord.major"
        case .Add4: return "builtin.chord.add4"
        case .Sixth: return "builtin.chord.major-6"
        case .SixNine: return "builtin.chord.six-nine"
        case .Maj7: return "builtin.chord.major-7"
        case .Maj9: return "builtin.chord.major-9"
        case .Maj11: return "builtin.chord.major-11"
        case .Maj13: return "builtin.chord.major-13"
        case .Maj7Sharp11: return "builtin.chord.major-7-sharp-11"
        case .Majb5: return "builtin.chord.major-flat-5"
        case .Min: return "builtin.chord.minor"
        case .MinAdd4: return "builtin.chord.minor-add4"
        case .Min6: return "builtin.chord.minor-6"
        case .Min7: return "builtin.chord.minor-7"
        case .MinAdd9: return "builtin.chord.minor-add9"
        case .Min6Add9: return "builtin.chord.minor-six-nine"
        case .Min9: return "builtin.chord.minor-9"
        case .Min11: return "builtin.chord.minor-11"
        case .Min13: return "builtin.chord.minor-13"
        case .MinMaj7: return "builtin.chord.minor-major-7"
        case .MinMaj9: return "builtin.chord.minor-major-9"
        case .MinMaj11: return "builtin.chord.minor-major-11"
        case .MinMaj13: return "builtin.chord.minor-major-13"
        case .Min7b5: return "builtin.chord.half-diminished-7"
        case .Dom7: return "builtin.chord.dominant-7"
        case .Dom9: return "builtin.chord.dominant-9"
        case .Dom11: return "builtin.chord.dominant-11"
        case .Dom13: return "builtin.chord.dominant-13"
        case .Dom7Sharp5: return "builtin.chord.dominant-7-sharp-5"
        case .Dom7b5: return "builtin.chord.dominant-7-flat-5"
        case .Dom7Sharp9: return "builtin.chord.dominant-7-sharp-9"
        case .Dom7b9: return "builtin.chord.dominant-7-flat-9"
        case .Dom9Sharp5: return "builtin.chord.dominant-9-sharp-5"
        case .Dom9b5: return "builtin.chord.dominant-9-flat-5"
        case .Dom7Sharp5Sharp9: return "builtin.chord.dominant-7-sharp-5-sharp-9"
        case .Dom7Sharp5b9: return "builtin.chord.dominant-7-sharp-5-flat-9"
        case .Dom7b5Sharp9: return "builtin.chord.dominant-7-flat-5-sharp-9"
        case .Dom7b5b9: return "builtin.chord.dominant-7-flat-5-flat-9"
        case .Dom7Sharp11: return "builtin.chord.dominant-7-sharp-11"
        case .Aug: return "builtin.chord.augmented"
        case .Dim: return "builtin.chord.diminished"
        case .Dim7: return "builtin.chord.diminished-7"
        case .Fifth: return "builtin.chord.power"
        case .FlatFifth: return "builtin.chord.flat-5-dyad"
        case .Sus4: return "builtin.chord.sus4"
        case .Sus2: return "builtin.chord.sus2"
        case .Sharp11: return "builtin.chord.sharp-11-no-3"
        }
    }
    
    var intervals: [Interval] {
        return Appendix.instance.chordIntervals[self]!
    }
    
    func getNotes(_ key: Note, inversion: Inversion = .Root) -> [Note] {
        return NoteService
            .getNotes(self.intervals, key: key)
                    .invert(inversion)
    }
}
