//
//  ScaleType.swift
//  ArpGen
//
//  Created by Brian on 27/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation

public enum ScaleType: CustomStringConvertible {
    
    // Major (w/Modes)
    case Major(_ mode: MajorModes)
    
    // (Natural) Minor
    case Minor
    
    // Harmonic Minor (w/Modes)
    case HarmonicMinor
    case Locrian13
    case IonianSharp5
    case DorianSharp11
    case PhrygianDominant
    case LydianSharp2
    case SuperLocrianbb7
    
    // Meoldic Minor (w/Modes)
    case MelodicMinor
    case Dorianb2
    case LydianAugmented
    case LydianDominant
    case Mixolydianb6
    case Aeolianb5
    case AlteredScale
    
    // Pentatonics
    case MajorPentatonic
    case MinorPentatonic
    
    // Blues
    case Blues(_ style: ScaleStyle)
    
    // Eastern
    // Wholetone & Diminished
    
    public var description: String {
        let mirror = Mirror(reflecting: self)
        return mirror.children.first?.label ?? String(describing: self)
    }
    
    var intervals: [Interval] {
        switch self {
        // Major Modes
        case .Major(let mode): do {
            switch mode {
            case .Ionian: return [.I, .II, .III, .IV, .V, .VI, .VII]
            case .Dorian: return [.I, .II, .bIII, .IV, .V, .VI, .bVII]
            case .Phrygian: return [.I, .bII, .bIII, .IV, .V, .bVI, .bVII]
            case .Lydian: return [.I, .II, .III, .bV, .V, .VI, .VII]
            case .Mixolydian: return [.I, .II, .III, .IV, .V, .VI, .bVII]
            case .Aeolian: return [.I, .II, .bIII, .IV, .V, .bVI, .bVII]
            case .Locrian: return [.I, .bII, .bIII, .IV, .bV, .bVI, .bVII]
            }
        }
        
        // (Natural) Minor
        case .Minor: return ScaleType.Major(.Aeolian).intervals
            
        // Harmonic Minor (w/Modes)
        case .HarmonicMinor: return [.I, .II, .bIII, .IV, .V, .bVI, .VII]
        case .Locrian13: return [.I, .bII, .bIII, .IV, .bV, .VI, .bVII]
        case .IonianSharp5: return [.I, .II, .III, .IV, .bVI, .VI, .VII]
        case .DorianSharp11: return [.I, .II, .bIII, .bV, .V, .VI, .bVII]
        case .PhrygianDominant: return [.I, .bII, .III, .IV, .V, .bVI, .bVII]
        case .LydianSharp2: return [.I, .bIII, .III, .bV, .V, .VI, .VII]
        case .SuperLocrianbb7: return [.I, .bII, .bIII, .III, .bV, .bVI, .bVII]
            
        // Meoldic Minor (w/Modes)
        case .MelodicMinor: return [.I, .II, .bIII, .IV, .V, .VI, .VII]
        case .Dorianb2: return [.I, .bII, .bIII, .IV, .V, .VI, .bVII]
        case .LydianAugmented: return [.I, .bII, .bIII, .bV, .bVI, .VI, .bVII]
        case .LydianDominant: return [.I, .II, .III, .bV, .V, .VI, .bVII]
        case .Mixolydianb6: return [.I, .II, .III, .IV, .V, .bVI, .bVII]
        case .Aeolianb5: return [.I, .II, .bIII, .IV, .bV, .bVI, .bVII]
        case .AlteredScale: return [.I, .bII, .bIII, .III, .bV, .bVI, .bVII]
            
            
        // Pentatonics
        case .MajorPentatonic: return [.I, .II, .III, .V, .VI]
        case .MinorPentatonic: return [.I, .bIII, .IV, .V, .bVII]
            
        // Blues
        case .Blues(let style): do {
            switch style {
            case .Pentatonic: return [.I, .II, .III, .V, .VI]
            case .Hexatonic: return [.I, .II, .III, .V, .VI]
            case .Heptatonic: return [.I, .II, .III, .V, .VI]
            case .Octatonic: return [.I, .II, .III, .V, .VI]
            case .Nonatonic: return [.I, .II, .III, .V, .VI]
            }
        }
            
        // Eastern
            
        // Wholetone & Diminished
        }
    }
    
    func getNotes(_ key: Note) -> [Note] {
        return NoteService
            .getNotes(self.intervals, key: key)
    }
}
