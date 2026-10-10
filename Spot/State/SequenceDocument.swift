//
//  SequenceDocument.swift
//  Spot
//

import SwiftUI
import UniformTypeIdentifiers
import SpotCore

extension UTType {
    /// `.spot`: a package folder with `sequence.json` (and, later, audio references and takes). Declared in Info.plist.
    static let spotSequence = UTType(exportedAs: "iko.spot.sequence", conformingTo: .package)
}

/// A song's chord sequence, saved as a `.spot` package.
struct SequenceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.spotSequence] }

    static let sequenceFilename = "sequence.json"

    var sequence: ChordSequence
    /// Other things to put in the package (recorded takes), by name.
    var extraFiles: [String: FileWrapper] = [:]
    
    init(sequence: ChordSequence = ChordSequence(), extraFiles: [String: FileWrapper] = [:]) {
        self.sequence = sequence
        self.extraFiles = extraFiles
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.fileWrappers?[SequenceDocument.sequenceFilename]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        sequence = try JSONDecoder().decode(ChordSequence.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Keep anything else in the package (audio references, takes) and replace only the sequence
        let package = configuration.existingFile?.isDirectory == true
            ? configuration.existingFile!
            : FileWrapper(directoryWithFileWrappers: [:])
        if let old = package.fileWrappers?[SequenceDocument.sequenceFilename] {
            package.removeFileWrapper(old)
        }
        package.addRegularFile(withContents: try sequence.encoded(), preferredFilename: SequenceDocument.sequenceFilename)
        for (name, wrapper) in extraFiles where package.fileWrappers?[name] == nil {
            wrapper.preferredFilename = name
            package.addFileWrapper(wrapper)
        }
        return package
    }
}
