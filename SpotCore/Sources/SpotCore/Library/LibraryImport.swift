//
//  LibraryImport.swift
//  SpotCore
//

import Foundation

/// Works out what importing a bundle would change, and applies the user's choices for clashes.
public struct LibraryImport: Sendable {
    public enum Resolution: String, CaseIterable, Sendable {
        /// Keep what's already there and ignore the incoming item.
        case skip
        /// Overwrite the existing item. Not possible for built-in items, which are kept as both instead.
        case replace
        /// Import as a new item with a fresh id and a "(2)" name.
        case keepBoth
    }

    public struct Item: Identifiable, Hashable, Sendable {
        public enum Kind: String, Sendable { case scale, chord, shape }

        public var id: String
        public var kind: Kind
        public var name: String
        /// Already exists in the library.
        public var isConflict: Bool
        /// The existing item is built in, so it can't be replaced.
        public var isBuiltIn: Bool
    }

    public let bundle: LibraryBundle
    public let items: [Item]
    /// Problems in the incoming file (see `LibraryBundle.validate`).
    public let issues: [String]

    /// - Parameters:
    ///   - existingIds: ids of everything in the library now, built-in and user.
    ///   - builtInIds: ids of built-in items, which can't be replaced.
    public init(_ bundle: LibraryBundle, existingIds: Set<String>, builtInIds: Set<String>) {
        self.bundle = bundle
        self.issues = bundle.validate()

        func item(_ id: String, _ kind: Item.Kind, _ name: String) -> Item {
            Item(id: id, kind: kind, name: name, isConflict: existingIds.contains(id), isBuiltIn: builtInIds.contains(id))
        }

        items = bundle.scales.map { item($0.id, .scale, $0.name) }
            + bundle.chords.map { item($0.id, .chord, $0.name) }
            + bundle.shapes.map { item($0.id, .shape, $0.name) }
    }

    public var conflicts: [Item] {
        items.filter(\.isConflict)
    }

    /// The bundle to add to the library, given a resolution for each clashing id (`default` for the rest).
    /// Kept-both items get new ids, and shapes that pointed at them follow.
    public func resolved(_ resolutions: [String: Resolution] = [:], default defaultResolution: Resolution = .keepBoth,
                         makeId: () -> String = { UUID().uuidString }) -> LibraryBundle {
        let conflictIds = Set(conflicts.map(\.id))
        let builtIn = Set(items.filter(\.isBuiltIn).map(\.id))
        var renamed: [String: String] = [:]
        var skipped = Set<String>()

        for id in conflictIds {
            var resolution = resolutions[id] ?? defaultResolution
            if resolution == .replace && builtIn.contains(id) {
                resolution = .keepBoth
            }
            switch resolution {
            case .skip: skipped.insert(id)
            case .replace: break
            case .keepBoth: renamed[id] = "user.\(makeId())"
            }
        }

        var result = bundle
        result.scales = bundle.scales.filter { !skipped.contains($0.id) }.map { scale in
            var scale = scale
            if let id = renamed[scale.id] {
                scale.id = id
                scale.name += " (2)"
            }
            if let parent = scale.parent, let id = renamed[parent.id] {
                scale.parent?.id = id
            }
            return scale
        }
        result.chords = bundle.chords.filter { !skipped.contains($0.id) }.map { chord in
            var chord = chord
            if let id = renamed[chord.id] {
                chord.id = id
                chord.name += " (2)"
            }
            return chord
        }
        result.shapes = bundle.shapes.filter { !skipped.contains($0.id) }.map { shape in
            var shape = shape
            if let id = renamed[shape.id] {
                shape.id = id
                shape.name += " (2)"
            }
            if let id = renamed[shape.definitionId] {
                shape.definitionId = id
            }
            return shape
        }
        return result
    }
}
