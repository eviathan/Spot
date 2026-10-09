//
//  Letter.swift
//  SpotCore
//

import Foundation

public enum Letter: Int, CaseIterable, Codable, Sendable, CustomStringConvertible {
    case C, D, E, F, G, A, B

    public var naturalPitchClass: PitchClass {
        PitchClass([0, 2, 4, 5, 7, 9, 11][rawValue])
    }

    public func advanced(by steps: Int) -> Letter {
        Letter(rawValue: ((rawValue + steps) % 7 + 7) % 7)!
    }

    public init?(_ character: Character) {
        guard let letter = Letter.allCases.first(where: { $0.description == String(character) }) else {
            return nil
        }
        self = letter
    }

    public var description: String {
        ["C", "D", "E", "F", "G", "A", "B"][rawValue]
    }
}
