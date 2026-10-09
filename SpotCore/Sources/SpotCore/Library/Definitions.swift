//
//  Definitions.swift
//  SpotCore
//

import Foundation

public struct ScaleDefinition: Identifiable, Hashable, Codable, Sendable {
    /// Links a mode to the scale it is a rotation of, e.g. Dorian → Major, degree 2.
    public struct ModeParent: Hashable, Codable, Sendable {
        public var id: String
        public var degree: Int

        public init(id: String, degree: Int) {
            self.id = id
            self.degree = degree
        }
    }

    public var id: String
    public var name: String
    public var aliases: [String]
    public var formula: Formula
    public var family: String?
    public var parent: ModeParent?
    public var tags: [String]

    public init(id: String, name: String, aliases: [String] = [], formula: Formula,
                family: String? = nil, parent: ModeParent? = nil, tags: [String] = []) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.formula = formula
        self.family = family
        self.parent = parent
        self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        formula = try container.decode(Formula.self, forKey: .formula)
        family = try container.decodeIfPresent(String.self, forKey: .family)
        parent = try container.decodeIfPresent(ModeParent.self, forKey: .parent)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

public struct ChordDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    /// Accepted symbols; the first is used for display. The major triad's first symbol is `""`.
    public var symbols: [String]
    public var formula: Formula
    /// Degrees that can be left out of a voicing (e.g. the 5th of a 9th chord).
    public var optional: Set<Degree>
    public var tags: [String]

    public init(id: String, name: String, symbols: [String], formula: Formula,
                optional: Set<Degree> = [], tags: [String] = []) {
        self.id = id
        self.name = name
        self.symbols = symbols
        self.formula = formula
        self.optional = optional
        self.tags = tags
    }

    public var displaySymbol: String {
        symbols.first ?? ""
    }

    public var requiredDegrees: [Degree] {
        formula.degrees.filter { !optional.contains($0) }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbols, formula, optional, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbols = try container.decode([String].self, forKey: .symbols)
        formula = try container.decode(Formula.self, forKey: .formula)
        optional = Set(try container.decodeIfPresent([Degree].self, forKey: .optional) ?? [])
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(symbols, forKey: .symbols)
        try container.encode(formula, forKey: .formula)
        if !optional.isEmpty {
            try container.encode(optional.sorted(), forKey: .optional)
        }
        if !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
    }
}
