//
//  LayoutView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI
import UniformTypeIdentifiers
import SpotCore

struct LayoutView: View {
    @Environment(UIState.self) private var ui
    @Environment(LibraryStore.self) private var library
    @Environment(SequenceSession.self) private var session
    @Environment(TabSession.self) private var tabSession
    @Environment(PlaybackController.self) private var playback
    @Environment(\.theme) private var theme

    let headerHeight: CGFloat = 52
    let footerHeight: CGFloat = 50

    var body: some View {
        @Bindable var ui = ui

        VStack(alignment:.leading, spacing: 0) {
            // A fixed height: without the fretboard below it (the expanded Library, Tab and Settings tabs), the
            // page would otherwise squeeze it away
            if !ui.isWindowFullScreen {
                Header()
                    .frame(maxWidth: .infinity)
                    .frame(height: Header.height)
                    .layoutPriority(1)
            }


            if ui.showsFretboardOnly {
                let sequenceOpen = ui.tab == .Sequence && session.sequence != nil && session.editor != nil

                if sequenceOpen, let sequence = session.sequence, let editor = session.editor {
                    FretboardReadout(sequence: sequence, editor: editor, card: .now)
                }

                InstrumentView()
                    .environment(\.fretboardMaxHeight, 620)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.fretboardBackground, ignoresSafeAreaEdges: [])

                if sequenceOpen, let sequence = session.sequence, let editor = session.editor {
                    FretboardReadout(sequence: sequence, editor: editor, card: .next)
                        .padding(.bottom, 16)
                }
            } else {
                if !ui.hidesFretboard {
                    InstrumentView()
                        .frame(maxWidth: .infinity)
                        .background(theme.fretboardBackground, ignoresSafeAreaEdges: [])
                }

                // Clipped: backgrounds reach up into the title bar area by default, which (with the fretboard hidden)
                // would paint over the header
                TabView ()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }

            Footer()
                .frame(maxWidth: .infinity, minHeight: footerHeight, maxHeight: footerHeight)
        }
        // Over everything while the recording gets ready; it closes up into the header
        .overlay(alignment: .top) { LoadingCurtain() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { ui.isWindowFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { ui.isWindowFullScreen = false }
        }
        .edgesIgnoringSafeArea(.all)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Opened straight into full screen (restored by macOS): no notification for that
            ui.isWindowFullScreen = NSApp.windows.contains { $0.styleMask.contains(.fullScreen) }
            SpaceBarMonitor.install { [ui, session, tabSession, playback] option in
                if option {
                    TransportActions.playSelection(ui: ui, session: session, tab: tabSession, playback: playback)
                } else {
                    TransportActions.playPause(ui: ui, session: session, tab: tabSession, playback: playback)
                }
            }
            DeleteKeyMonitor.install { [ui, session] in
                guard ui.tab == .Sequence, session.isOpen, let editor = session.editor, editor.selection.length > 0 else {
                    return false
                }
                session.deleteSelection()
                return true
            }
        }
        .sheet(item: $ui.definitionEditor) { request in
            DefinitionEditorView(request: request)
        }
        .sheet(item: $ui.pendingImport) { pending in
            ImportReviewView(pending: pending)
        }
        .sheet(isPresented: $ui.isChoosingExport, onDismiss: {
            if ui.exportFile != nil {
                ui.isExporting = true
            }
        }) {
            ExportOptionsView()
        }
        // One Open and one Save panel for the whole window: SwiftUI ignores nested ones on macOS
        .fileImporter(isPresented: Binding(get: { ui.openPanel != nil }, set: { if !$0 { ui.openPanel = nil } }),
                      allowedContentTypes: ui.openPanel?.contentTypes ?? ui.lastOpenPanel.contentTypes) { result in
            handleOpen(result, panel: ui.lastOpenPanel)
        }
        .fileExporter(isPresented: Binding(get: { ui.savePanel != nil }, set: { if !$0 { ui.savePanel = nil } }),
                      document: exportDocument,
                      contentType: saveType,
                      defaultFilename: saveName) { result in
            handleSave(result, panel: ui.lastSavePanel)
        }
        // An Untitled tab with changes, about to be replaced
        .confirmationDialog("Save changes to “\(tabSession.displayName)”?",
                            isPresented: Binding(get: { ui.pendingTabAction != nil },
                                                 set: { if !$0 { ui.pendingTabAction = nil } }),
                            titleVisibility: .visible) {
            Button("Save…") {
                ui.tabActionAfterSave = ui.pendingTabAction
                ui.pendingTabAction = nil
                ui.savePanel = .tab
            }
            Button("Don't Save", role: .destructive) {
                if let action = ui.pendingTabAction {
                    ui.pendingTabAction = nil
                    ui.perform(action, session: tabSession)
                }
            }
            Button("Cancel", role: .cancel) { ui.pendingTabAction = nil }
        } message: {
            Text("This tab hasn't been saved to a file yet.")
        }
        .confirmationDialog("Save changes to “\(session.displayName)”?",
                            isPresented: Binding(get: { ui.pendingSequenceAction != nil },
                                                 set: { if !$0 { ui.pendingSequenceAction = nil } }),
                            titleVisibility: .visible) {
            Button("Save…") {
                ui.sequenceActionAfterSave = ui.pendingSequenceAction
                ui.pendingSequenceAction = nil
                ui.isSavingSequenceAs = true
            }
            Button("Don't Save", role: .destructive) {
                if let action = ui.pendingSequenceAction {
                    ui.pendingSequenceAction = nil
                    ui.perform(action, session: session)
                }
            }
            Button("Cancel", role: .cancel) { ui.pendingSequenceAction = nil }
        } message: {
            Text("This sequence hasn't been saved to a file yet.")
        }
        .onOpenURL { url in
            if url.pathExtension == "spot" {
                ui.requestSequenceAction(.openURL(url), session: session)
            } else if url.pathExtension == "spottab" || GuitarPro.fileExtensions.contains(url.pathExtension.lowercased()) {
                ui.requestTabAction(.openURL(url), session: tabSession)
            } else {
                openLibraryFile(url)
            }
        }
        .alert("Some tracks weren't brought in",
               isPresented: Binding(get: { tabSession.skippedOnImport != nil }, set: { if !$0 { tabSession.skippedOnImport = nil } })) {
            Button("OK") { tabSession.skippedOnImport = nil }
        } message: {
            Text("Drum tracks can't be shown as tab, so these were left out: \((tabSession.skippedOnImport ?? []).joined(separator: ", ")).")
        }
        .alert("Something went wrong", isPresented: Binding(get: { ui.errorMessage != nil }, set: { if !$0 { ui.errorMessage = nil } })) {
            Button("OK") { ui.errorMessage = nil }
        } message: {
            Text(ui.errorMessage ?? "")
        }
    }

    /// What the Save panel writes: the library export or the open sequence.
    /// Only made while the panel is up: building it reads the sequence (and the takes folder), and doing
    /// that on every render would redraw the whole window whenever a chord changed.
    @MainActor
    private var exportDocument: ExportDocument? {
        guard ui.savePanel != nil else { return nil }
        switch ui.lastSavePanel {
        case .library: return ui.exportFile.map { ExportDocument(.library($0)) }
        case .sequence: return session.document.map { ExportDocument(.sequence($0)) }
        case .tab: return tabSession.document.map { ExportDocument(.tab($0)) }
        case .guitarPro: return tabSession.guitarProDocument.map { ExportDocument(.guitarPro($0)) }
        case .tabPDF: return tabSession.printContent.map { ExportDocument(.pdf(PDFFile(data: TabPrinter.pdf($0)))) }
        }
    }

    private func handleOpen(_ result: Result<URL, Error>, panel: OpenPanel) {
        let url: URL
        switch result {
        case .success(let chosen): url = chosen
        case .failure(let error):
            ui.errorMessage = error.localizedDescription
            return
        }

        switch panel {
        case .library:
            openLibraryFile(url)
        case .sequence:
            ui.requestSequenceAction(.openURL(url), session: session)
        case .tab:
            ui.requestTabAction(.openURL(url), session: tabSession)
        case .audio, .relinkAudio:
            do {
                try panel == .relinkAudio ? session.relinkAudio(url) : session.importAudio(url)
            } catch {
                ui.errorMessage = "Couldn't use that audio file: \(error.localizedDescription)"
            }
        }
    }

    private func handleSave(_ result: Result<URL, Error>, panel: SavePanel) {
        switch (panel, result) {
        case (.library, .success):
            ui.exportFile = nil
        case (.library, .failure(let error)):
            ui.errorMessage = error.localizedDescription
            ui.exportFile = nil
        case (.sequence, .success(let url)):
            session.didSave(to: url)
            if let next = ui.sequenceActionAfterSave {
                ui.sequenceActionAfterSave = nil
                ui.perform(next, session: session)
            }
        case (.sequence, .failure(let error)):
            ui.errorMessage = error.localizedDescription
            ui.sequenceActionAfterSave = nil
        case (.tab, .success(let url)):
            tabSession.didSave(to: url)
            if let next = ui.tabActionAfterSave {
                ui.tabActionAfterSave = nil
                ui.perform(next, session: tabSession)
            }
        case (.tab, .failure(let error)):
            ui.errorMessage = error.localizedDescription
            ui.tabActionAfterSave = nil
        case (.guitarPro, .success), (.tabPDF, .success):
            break
        case (.guitarPro, .failure(let error)), (.tabPDF, .failure(let error)):
            ui.errorMessage = error.localizedDescription
        }
    }

    private var saveType: UTType {
        switch ui.lastSavePanel {
        case .library: return .spotLibrary
        case .sequence: return .spotSequence
        case .tab: return .spotTab
        case .guitarPro: return .guitarPro7
        case .tabPDF: return .pdf
        }
    }

    private var saveName: String {
        switch ui.lastSavePanel {
        case .library: return ui.exportFile?.bundle.bundle.name ?? "Library"
        case .sequence: return session.displayName
        case .tab, .guitarPro, .tabPDF: return tabSession.score.map { $0.title.isEmpty ? tabSession.displayName : $0.title } ?? "Untitled"
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
