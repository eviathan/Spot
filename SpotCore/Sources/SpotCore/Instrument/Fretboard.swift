//
//  Fretboard.swift
//  SpotCore
//

import Foundation

/// Somewhere a pitch can be played. Each instrument defines its own positions;
/// the keyboard layout (positions = MIDI notes) comes later.
public protocol InstrumentLayout {
    associatedtype Position: Hashable

    var allPositions: [Position] { get }
    func pitchClass(at position: Position) -> PitchClass
}

extension InstrumentLayout {
    public func positions(of pitchClass: PitchClass) -> [Position] {
        allPositions.filter { self.pitchClass(at: $0) == pitchClass }
    }
}

public struct FretPosition: Hashable, Sendable, CustomStringConvertible {
    /// 0 is the lowest-pitched string.
    public var string: Int
    /// 0 is the open string.
    public var fret: Int

    public init(string: Int, fret: Int) {
        self.string = string
        self.fret = fret
    }

    public var description: String {
        "string \(string) fret \(fret)"
    }
}

public struct Fretboard: InstrumentLayout, Hashable, Sendable {
    public var tuning: Tuning
    public var fretCount: Int

    public init(tuning: Tuning = .standard, fretCount: Int = 24) {
        self.tuning = tuning
        self.fretCount = fretCount
    }

    public var stringCount: Int {
        tuning.strings.count
    }

    public var allPositions: [FretPosition] {
        (0..<stringCount).flatMap { string in
            (0...fretCount).map { FretPosition(string: string, fret: $0) }
        }
    }

    public func midiNote(at position: FretPosition) -> Int {
        tuning.strings[position.string] + position.fret
    }

    public func pitchClass(at position: FretPosition) -> PitchClass {
        PitchClass(midiNote(at: position))
    }
}
