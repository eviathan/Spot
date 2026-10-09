//
//  Appendix.swift
//  SongBook
//
//  Created by Brian on 29/12/2018.
//  Copyright © 2018 Eviathan. All rights reserved.
//

import Foundation
import SpotCore

// TODO: Remove once views use SpotCore definitions directly (see Plan.md, step 3)
public class Appendix {

    static let instance = Appendix()

    let library: LibraryBundle
    let scaleIntervals: [ScaleType: [Interval]]
    let chordIntervals: [ChordType: [Interval]]

    public var chordTypes: [[Interval]:ChordType] = [[Interval]:ChordType]()

    private init() {
        do {
            library = try LibraryBundle.builtIn()
        } catch {
            fatalError("Built-in library failed to load: \(error)")
        }

        let scalesById = Dictionary(uniqueKeysWithValues: library.scales.map { ($0.id, $0) })
        let chordsById = Dictionary(uniqueKeysWithValues: library.chords.map { ($0.id, $0) })

        scaleIntervals = Dictionary(uniqueKeysWithValues: ScaleType.allCases.map { scaleType in
            guard let scale = scalesById[scaleType.definitionId] else {
                fatalError("Built-in library has no scale \(scaleType.definitionId)")
            }
            return (scaleType, scale.formula.degrees.map(Interval.init(degree:)))
        })

        chordIntervals = Dictionary(uniqueKeysWithValues: ChordType.allCases.map { chordType in
            guard let chord = chordsById[chordType.definitionId] else {
                fatalError("Built-in library has no chord \(chordType.definitionId)")
            }
            return (chordType, chord.formula.degrees.map(Interval.init(degree:)))
        })

        // Built from the local table: ChordType.intervals reads Appendix.instance, which isn't ready yet
        chordTypes = chordIntervals.reduce(into: [[Interval]: ChordType]()) {
            $0[$1.value] = $1.key
        }
    }
}

extension Interval {
    /// Closest legacy interval for a spelled degree. Spelling is lost (bb7 becomes .VI, #5 becomes .bVI).
    init(degree: Degree) {
        self = Interval(rawValue: degree.semitones)
            ?? Interval(rawValue: degree.pitchClassOffset)
            ?? .I
    }
}
