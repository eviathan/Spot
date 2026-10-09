//
//  Formula.swift
//  SpotCore
//

import Foundation

/// The spelled degrees of a scale or chord, e.g. `1 b3 5 b7`.
public struct Formula: Hashable, Sendable, CustomStringConvertible, LosslessStringConvertible {
    public let degrees: [Degree]

    public init(_ degrees: [Degree]) {
        self.degrees = degrees
    }

    /// Parses a space- or comma-separated list such as `"1 b3 5 b7"`.
    public init?(_ description: String) {
        let parts = description
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
        let degrees = parts.compactMap(Degree.init)

        guard !degrees.isEmpty, degrees.count == parts.count else {
            return nil
        }

        self.init(degrees)
    }

    /// Distinct pitch classes relative to the root, 0...11.
    public var pitchClassOffsets: Set<Int> {
        Set(degrees.map(\.pitchClassOffset))
    }

    public func pitchClasses(from root: PitchClass) -> [PitchClass] {
        degrees.map { root.transposed(by: $0.semitones) }
    }

    public func spelled(from root: SpelledNote) -> [SpelledNote] {
        degrees.map(root.spelling)
    }

    /// Pitch classes of the mode starting on `degree` (1-based index into `degrees`),
    /// relative to that mode's own root. Dorian is the major formula's mode 2.
    public func modePitchClassOffsets(startingAt degree: Int) -> Set<Int> {
        let newRoot = degrees[degree - 1].pitchClassOffset
        return Set(degrees.map { PitchClass($0.pitchClassOffset - newRoot).value })
    }

    public var description: String {
        degrees.map(\.description).joined(separator: " ")
    }

    public var prettyDescription: String {
        degrees.map(\.prettyDescription).joined(separator: " ")
    }
}

extension Formula: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let formula = Formula(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid formula \"\(string)\"")
        }
        self = formula
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
