//
//  LibraryItemState.swift
//  Spot
//

import Foundation
import SwiftData

/// The user's own data about a library item, kept apart from the definition itself
/// so built-in definitions can be updated without losing favourites.
@Model
final class LibraryItemState {
    @Attribute(.unique) var definitionId: String
    var favourite: Bool
    var rating: Int
    var tags: [String]

    init(definitionId: String, favourite: Bool = false, rating: Int = 0, tags: [String] = []) {
        self.definitionId = definitionId
        self.favourite = favourite
        self.rating = rating
        self.tags = tags
    }
}
