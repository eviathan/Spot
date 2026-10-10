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

/// Whatever the window's single Save panel is saving: a library export, a sequence or a tab.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.spotLibrary, .spotSequence, .spotTab] }

    enum Content {
        case library(LibraryFile)
        case sequence(SequenceDocument)
        case tab(TabDocument)
    }

    var content: Content

    init(_ content: Content) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        switch content {
        case .library(let file): return try file.fileWrapper(configuration: configuration)
        case .sequence(let document): return try document.fileWrapper(configuration: configuration)
        case .tab(let document): return try document.fileWrapper(configuration: configuration)
        }
    }
}
