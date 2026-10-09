//
//  ScaleType.swift
//  ArpGen
//
//  Created by Brian on 27/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

public enum ScaleType: String, CaseIterable, CustomStringConvertible, Hashable, NoteCollection {
    // Major Modes
    case Major = "Major / Ionian"
    case Dorian = "Dorian"
    case Phrygian = "Phrygian"
    case Lydian = "Lydian"
    case Mixolydian = "Mixolydian"
    case Minor = "Minor / Aolian / Natural"
    case Locrian = "Locrian"
    
    // Harmonic Minor (w/Modes)
    case HarmonicMinor = "Harmonic Minor"
    case Locrian13 = "Locrian 13"
    case IonianSharp5 = "Ionian Sharp 5"
    case DorianSharp11 = "Dorian Sharp 11"
    case PhrygianDominant = "Phrygian Dominant"
    case LydianSharp2 = "Lydian Sharp 2"
    case SuperLocrianbb7 = "Super Locrian bb7"
    
    // Meoldic Minor (w/Modes)
    case MelodicMinor = "Melodic Minor"
    case Dorianb2 = "Dorian b2"
    case LydianAugmented = "Lydian Augmented"
    case LydianDominant = "Lydian Dominant"
    case Mixolydianb6 = "Mixolydian b6"
    case Aeolianb5 = "Aeolian b5"
    case AlteredScale = "Altered Scale"
    
    // Pentatonics
    case MajorPentatonic = "Major Pentatonic"
    case MinorPentatonic = "Minor Pentatonic"
    
    // Blues
    case Blues = "Blues"
    
    case Chromatic = "Chromatic"
    
    // Eastern
    // Wholetone & Diminished
    
    public var description: String {
        return self.rawValue
    }
    
    /// The matching definition in SpotCore's built-in library, which now holds the formulas
    var definitionId: String {
        switch self {
        case .Major: return "builtin.scale.major"
        case .Dorian: return "builtin.scale.dorian"
        case .Phrygian: return "builtin.scale.phrygian"
        case .Lydian: return "builtin.scale.lydian"
        case .Mixolydian: return "builtin.scale.mixolydian"
        case .Minor: return "builtin.scale.natural-minor"
        case .Locrian: return "builtin.scale.locrian"
        case .HarmonicMinor: return "builtin.scale.harmonic-minor"
        case .Locrian13: return "builtin.scale.locrian-natural-6"
        case .IonianSharp5: return "builtin.scale.ionian-sharp-5"
        case .DorianSharp11: return "builtin.scale.dorian-sharp-4"
        case .PhrygianDominant: return "builtin.scale.phrygian-dominant"
        case .LydianSharp2: return "builtin.scale.lydian-sharp-2"
        case .SuperLocrianbb7: return "builtin.scale.super-locrian-bb7"
        case .MelodicMinor: return "builtin.scale.melodic-minor"
        case .Dorianb2: return "builtin.scale.dorian-b2"
        case .LydianAugmented: return "builtin.scale.lydian-augmented"
        case .LydianDominant: return "builtin.scale.lydian-dominant"
        case .Mixolydianb6: return "builtin.scale.mixolydian-b6"
        case .Aeolianb5: return "builtin.scale.aeolian-b5"
        case .AlteredScale: return "builtin.scale.altered"
        case .MajorPentatonic: return "builtin.scale.major-pentatonic"
        case .MinorPentatonic: return "builtin.scale.minor-pentatonic"
        case .Blues: return "builtin.scale.blues"
        case .Chromatic: return "builtin.scale.chromatic"
        }
    }
    
    var intervals: [Interval] {
        return Appendix.instance.scaleIntervals[self]!
    }
    
    func getNotes(_ key: Note, inversion: Inversion = .Root) -> [Note] {
        return NoteService
            .getNotes(self.intervals, key: key)
    }
}
