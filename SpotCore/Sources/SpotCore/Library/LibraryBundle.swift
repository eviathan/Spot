//
//  LibraryBundle.swift
//  SpotCore
//

import Foundation

public enum LibraryBundleError: Error, Equatable {
    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case missingBuiltIn
}

/// The import/export format (`.spotlib`), also used for the built-in library.
public struct LibraryBundle: Hashable, Codable, Sendable {
    public static let formatIdentifier = "spot.library"
    public static let currentVersion = 1

    public struct Info: Hashable, Codable, Sendable {
        public var id: String
        public var name: String
        public var author: String?

        public init(id: String, name: String, author: String? = nil) {
            self.id = id
            self.name = name
            self.author = author
        }
    }

    public var format: String
    public var version: Int
    public var bundle: Info
    public var scales: [ScaleDefinition]
    public var chords: [ChordDefinition]
    /// Shapes for definitions in this bundle or in the built-in library.
    public var shapes: [Shape]
    public var tunings: [Tuning]

    public init(bundle: Info, scales: [ScaleDefinition] = [], chords: [ChordDefinition] = [],
                shapes: [Shape] = [], tunings: [Tuning] = []) {
        self.format = LibraryBundle.formatIdentifier
        self.version = LibraryBundle.currentVersion
        self.bundle = bundle
        self.scales = scales
        self.chords = chords
        self.shapes = shapes
        self.tunings = tunings
    }

    enum CodingKeys: String, CodingKey {
        case format, version, bundle, scales, chords, shapes, tunings
    }

    // Every list is optional in files, so a bundle can hold just chords, or just shapes
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        bundle = try container.decode(Info.self, forKey: .bundle)
        scales = try container.decodeIfPresent([ScaleDefinition].self, forKey: .scales) ?? []
        chords = try container.decodeIfPresent([ChordDefinition].self, forKey: .chords) ?? []
        shapes = try container.decodeIfPresent([Shape].self, forKey: .shapes) ?? []
        tunings = try container.decodeIfPresent([Tuning].self, forKey: .tunings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(version, forKey: .version)
        try container.encode(bundle, forKey: .bundle)
        try container.encode(scales, forKey: .scales)
        try container.encode(chords, forKey: .chords)
        if !shapes.isEmpty {
            try container.encode(shapes, forKey: .shapes)
        }
        if !tunings.isEmpty {
            try container.encode(tunings, forKey: .tunings)
        }
    }

    public static func decode(from data: Data) throws -> LibraryBundle {
        struct Header: Decodable {
            var format: String
            var version: Int
        }

        // Check the header first so a newer file gives a clear error rather than a decoding failure
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.format == formatIdentifier else {
            throw LibraryBundleError.unsupportedFormat(header.format)
        }
        guard header.version <= currentVersion else {
            throw LibraryBundleError.unsupportedVersion(header.version)
        }

        return try JSONDecoder().decode(LibraryBundle.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The library shipped with the app.
    public static func builtIn() throws -> LibraryBundle {
        guard let url = Bundle.module.url(forResource: "BuiltInLibrary", withExtension: "json") else {
            throw LibraryBundleError.missingBuiltIn
        }
        return try decode(from: Data(contentsOf: url))
    }

    /// Problems that would make the bundle misbehave: duplicate ids or symbols,
    /// malformed formulas, and modes that don't match their parent scale.
    public func validate() -> [String] {
        var issues: [String] = []

        let ids = scales.map(\.id) + chords.map(\.id) + shapes.map(\.id)
        for (id, count) in Dictionary(grouping: ids, by: { $0 }).mapValues(\.count) where count > 1 {
            issues.append("Duplicate id \(id)")
        }

        let scalesById = Dictionary(scales.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for scale in scales {
            issues += LibraryBundle.formulaIssues(scale.formula, id: scale.id)

            if let parent = scale.parent {
                if let parentScale = scalesById[parent.id] {
                    if !parentScale.formula.degrees.indices.contains(parent.degree - 1) {
                        issues.append("\(scale.id): parent degree \(parent.degree) out of range")
                    } else if parentScale.formula.modePitchClassOffsets(startingAt: parent.degree) != scale.formula.pitchClassOffsets {
                        issues.append("\(scale.id): formula is not mode \(parent.degree) of \(parent.id)")
                    }
                } else {
                    issues.append("\(scale.id): unknown parent \(parent.id)")
                }
            }
        }

        var symbolOwners: [String: String] = [:]
        for chord in chords {
            issues += LibraryBundle.formulaIssues(chord.formula, id: chord.id)

            if chord.symbols.isEmpty {
                issues.append("\(chord.id): no symbols")
            }
            for symbol in chord.symbols {
                if let owner = symbolOwners[symbol], owner != chord.id {
                    issues.append("Symbol \"\(symbol)\" used by both \(owner) and \(chord.id)")
                }
                symbolOwners[symbol] = chord.id
            }
            for degree in chord.optional where !chord.formula.degrees.contains(degree) {
                issues.append("\(chord.id): optional degree \(degree) is not in the formula")
            }
        }

        // Shapes may belong to definitions elsewhere (e.g. built-in ones); check those in this bundle
        let formulas = Dictionary(scales.map { ($0.id, $0.formula) } + chords.map { ($0.id, $0.formula) },
                                  uniquingKeysWith: { first, _ in first })
        for shape in shapes {
            if shape.notes.isEmpty {
                issues.append("\(shape.id): shape has no notes")
            }
            if shape.notes.contains(where: { $0.string < 0 }) {
                issues.append("\(shape.id): negative string number")
            }
            if let formula = formulas[shape.definitionId] {
                let offsets = formula.pitchClassOffsets
                if shape.notes.contains(where: { !offsets.contains($0.degree.pitchClassOffset) }) {
                    issues.append("\(shape.id): has notes outside \(shape.definitionId)")
                }
            }
        }

        return issues
    }

    private static func formulaIssues(_ formula: Formula, id: String) -> [String] {
        var issues: [String] = []
        let semitones = formula.degrees.map(\.semitones)

        if formula.degrees.first != Degree(1) {
            issues.append("\(id): formula must start with 1")
        }
        if semitones != semitones.sorted() || Set(semitones).count != semitones.count {
            issues.append("\(id): degrees must be strictly ascending")
        }
        if formula.pitchClassOffsets.count != formula.degrees.count {
            issues.append("\(id): two degrees share a pitch class")
        }

        return issues
    }
}
