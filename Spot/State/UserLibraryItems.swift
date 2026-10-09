//
//  UserLibraryItems.swift
//  Spot
//

import Foundation
import SwiftData

/// A scale or chord you made or imported. Stored as the same JSON as a `.spotlib` file,
/// so the definition types live in one place (SpotCore).
@Model
final class UserDefinition {
    @Attribute(.unique) var definitionId: String
    /// "scale" or "chord".
    var kind: String
    var data: Data
    /// Name of the bundle it was imported from; nil for your own.
    var source: String?
    var createdAt: Date

    init(definitionId: String, kind: String, data: Data, source: String?) {
        self.definitionId = definitionId
        self.kind = kind
        self.data = data
        self.source = source
        self.createdAt = .now
    }
}

/// A shape you made or imported, for any definition (built-in or yours).
@Model
final class UserShape {
    @Attribute(.unique) var shapeId: String
    var definitionId: String
    var data: Data
    var source: String?
    var createdAt: Date

    init(shapeId: String, definitionId: String, data: Data, source: String?) {
        self.shapeId = shapeId
        self.definitionId = definitionId
        self.data = data
        self.source = source
        self.createdAt = .now
    }
}
