//
//  SpotApp.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI
import SwiftData
import SpotCore

@main
struct SpotApp: App {
    private let container: ModelContainer

    @State private var library: LibraryStore
    @State private var selection: SelectionState
    @State private var display = DisplaySettings()
    @State private var ui = UIState()
    @State private var transport: TransportState
    @State private var audioSettings: AudioSettings
    @State private var playback: PlaybackController
    @State private var practice: PracticeState
    @State private var session: SequenceSession

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false

        let builtIn: LibraryBundle
        do {
            builtIn = try LibraryBundle.builtIn()
            container = try ModelContainer(for: LibraryItemState.self, UserDefinition.self, UserShape.self,
                                           configurations: ModelConfiguration("Spot"))
        } catch {
            fatalError("Failed to start: \(error)")
        }

        let library = LibraryStore(bundle: builtIn, context: container.mainContext)
        _library = State(initialValue: library)
        _selection = State(initialValue: SelectionState(scale: builtIn.scales[0], chord: builtIn.chords[0], library: library))
        
        let transport = TransportState()
        let audioSettings = AudioSettings()
        _transport = State(initialValue: transport)
        _audioSettings = State(initialValue: audioSettings)
        let playback = PlaybackController(transport: transport, settings: audioSettings)
        _playback = State(initialValue: playback)
        _practice = State(initialValue: PracticeState(library: library))
        _session = State(initialValue: SequenceSession(library: library, playback: playback, transport: transport))
    }

    var body: some Scene {
        WindowGroup() {
            LayoutView()
                .frame(minWidth: 1280, minHeight: 800)
                .environment(library)
                .environment(selection)
                .environment(display)
                .environment(ui)
                .environment(transport)
                .environment(audioSettings)
                .environment(playback)
                .environment(practice)
                .environment(session)
                .toolbar {
                    Color.clear
                }
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sequence") { ui.requestSequenceAction(.new, session: session) }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Open Sequence…") { ui.requestSequenceAction(.open, session: session) }
                    .keyboardShortcut("o", modifiers: [.command])
                Menu("Open Recent") {
                    ForEach(session.recents) { recent in
                        Button(recent.name) { ui.requestSequenceAction(.openRecent(recent), session: session) }
                    }
                }
                .disabled(session.recents.isEmpty)
                Button("Close Sequence") { ui.requestSequenceAction(.close, session: session) }
                    .disabled(!session.isOpen)
                Divider()
                Button("New Scale…") { ui.definitionEditor = .new(.scale) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Chord…") { ui.definitionEditor = .new(.chord) }
                    .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    if session.fileURL == nil {
                        ui.isSavingSequenceAs = true
                    } else {
                        do { try session.save() } catch { ui.errorMessage = error.localizedDescription }
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!session.isOpen)
                Button("Save As…") { ui.isSavingSequenceAs = true }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!session.isOpen)
            }
            
            CommandGroup(replacing: .importExport) {
                Button("Import Library…") { ui.isImporting = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export Library…") { ui.isChoosingExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            
            CommandMenu("Playback") {
                Button(transport.isPlaying ? "Stop" : "Play") {
                    if ui.tab == .Sequence && session.isOpen && !transport.isPlaying {
                        session.togglePlay()
                    } else {
                        playback.togglePlay()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command])
                Button(transport.isMetronomeOn ? "Metronome Off" : "Metronome On") { transport.isMetronomeOn.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button(ui.tab == .Practice ? "Preview Chord" : "Preview Shape") { previewCurrentShape() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(ui.tab == .Sequence)
            }
            
            CommandMenu("Shape") {
                Button(ui.tab == .Practice ? "Next Voicing" : "Next Shape") {
                    ui.tab == .Practice ? practice.nextVoicing() : selection.nextShape()
                }
                .keyboardShortcut("]", modifiers: [.command])
                Button(ui.tab == .Practice ? "Previous Voicing" : "Previous Shape") {
                    ui.tab == .Practice ? practice.previousVoicing() : selection.previousShape()
                }
                .keyboardShortcut("[", modifiers: [.command])
                Divider()
                Button("Next Chord") { practice.nextChord() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(ui.tab != .Practice)
                Button("Previous Chord") { practice.previousChord() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(ui.tab != .Practice)
                Divider()
                Button("New Shape") { selection.startNewShape(copyingCurrent: false) }
                    .disabled(selection.kind == .interval)
                Button("Copy Shape to Edit") { selection.startNewShape(copyingCurrent: true) }
                    .disabled(selection.currentShape == nil)
            }

            CommandGroup(before: .toolbar) {
                Button("Toggle Unrelated Notes") {
                    display.hideUnrelatedNotes.toggle()
                }
                .keyboardShortcut("U", modifiers: [.command])
                Button("Toggle Shape Isolation") {
                    display.isolatePosition.toggle()
                }
                .keyboardShortcut("I", modifiers: [.command])
                Button("Toggle Highlight All Shapes") {
                    display.highlightAllPositions.toggle()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
                Button("Cycle Labels (Interval / Note / Finger)") {
                    display.markerLabel = display.markerLabel.next
                }
                .keyboardShortcut("L", modifiers: [.command])
            }
       }
    }
    
    private func previewCurrentShape() {
        if ui.tab == .Practice {
            playback.preview(practice.chordEvents(clock: transport.clock))
            return
        }
        guard let shape = selection.currentShape,
              let placement = shape.placements(root: selection.root, on: selection.fretboard).first else { return }
        playback.preview(Audition.events(for: shape, placement: placement, on: selection.fretboard, clock: transport.clock))
    }
}
