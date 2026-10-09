//
//  LibraryFile.swift
//  Spot
//

import SwiftUI
import UniformTypeIdentifiers
import SpotCore

extension UTType {
    /// `.spotlib`: a LibraryBundle as JSON. Declared in Info.plist.
    static let spotLibrary = UTType(exportedAs: "iko.spot.library", conformingTo: .json)
}

/// Wraps a LibraryBundle for SwiftUI's file importer/exporter.
struct LibraryFile: FileDocument {
    static var readableContentTypes: [UTType] { [.spotLibrary, .json] }

    var bundle: LibraryBundle

    init(bundle: LibraryBundle) {
        self.bundle = bundle
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        bundle = try LibraryBundle.decode(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try bundle.encoded())
    }
}
