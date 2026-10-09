//
//  LayoutView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI
import SpotCore

struct LayoutView: View {
    @Environment(UIState.self) private var ui
    @Environment(LibraryStore.self) private var library

    let headerHeight: CGFloat = 52
    let footerHeight: CGFloat = 50

    var body: some View {
        @Bindable var ui = ui

        VStack(alignment:.leading, spacing: 0) {
            Header()
                .frame(maxWidth: .infinity)


            InstrumentView()
                .frame(maxWidth: .infinity)

            TabView ()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Footer()
                .frame(maxWidth: .infinity, minHeight: footerHeight, maxHeight: footerHeight)
        }
        .edgesIgnoringSafeArea(.all)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $ui.definitionEditor) { request in
            DefinitionEditorView(request: request)
        }
        .sheet(item: $ui.pendingImport) { pending in
            ImportReviewView(pending: pending)
        }
        .sheet(isPresented: $ui.isChoosingExport, onDismiss: {
            // The save panel can only open once the options sheet has gone
            if ui.exportFile != nil {
                ui.isExporting = true
            }
        }) {
            ExportOptionsView()
        }
        .fileImporter(isPresented: $ui.isImporting, allowedContentTypes: [.spotLibrary, .json]) { result in
            switch result {
            case .success(let url): openLibraryFile(url)
            case .failure(let error): ui.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $ui.isExporting, document: ui.exportFile, contentType: .spotLibrary,
                      defaultFilename: ui.exportFile?.bundle.bundle.name ?? "Library") { result in
            if case .failure(let error) = result {
                ui.errorMessage = error.localizedDescription
            }
            ui.exportFile = nil
        }
        .onOpenURL(perform: openLibraryFile)
        .alert("Something went wrong", isPresented: Binding(get: { ui.errorMessage != nil }, set: { if !$0 { ui.errorMessage = nil } })) {
            Button("OK") { ui.errorMessage = nil }
        } message: {
            Text(ui.errorMessage ?? "")
        }
    }

    /// Reads a `.spotlib` and shows what importing it would do.
    private func openLibraryFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let bundle = try LibraryBundle.decode(from: Data(contentsOf: url))
            ui.pendingImport = PendingImport(plan: library.importPlan(for: bundle))
        } catch LibraryBundleError.unsupportedVersion(let version) {
            ui.errorMessage = "This library was made by a newer version of Spot (format \(version))."
        } catch LibraryBundleError.unsupportedFormat {
            ui.errorMessage = "This file isn't a Spot library."
        } catch {
            ui.errorMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
