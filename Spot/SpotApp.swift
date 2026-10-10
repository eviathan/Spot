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
    @State private var tabSession: TabSession
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
        let session = SequenceSession(library: library, playback: playback, transport: transport)
        _session = State(initialValue: session)
        let tabSession = TabSession(playback: playback, transport: transport)
        tabSession.sequenceSession = session
        _tabSession = State(initialValue: tabSession)
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
                .environment(tabSession)
                .environment(session)
                .toolbar {
                    Color.clear
                }
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: false))
        .commands {
            // New, Open, Close and Save act on the Tab tab's file when it's showing, otherwise on the sequence
            CommandGroup(replacing: .newItem) {
                if ui.tab == .Tab {
                    Button("New Tab") { ui.requestTabAction(.new, session: tabSession) }
                        .keyboardShortcut("n", modifiers: [.command])
                    Button("Open Tab…") { ui.requestTabAction(.open, session: tabSession) }
                        .keyboardShortcut("o", modifiers: [.command])
                    Menu("Open Recent") {
                        ForEach(tabSession.recents) { recent in
                            Button(recent.name) { ui.requestTabAction(.openRecent(recent), session: tabSession) }
                        }
                    }
                    .disabled(tabSession.recents.isEmpty)
                    Button("Close Tab") { ui.requestTabAction(.close, session: tabSession) }
                        .disabled(!tabSession.isOpen)
                } else {
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
                }
                Divider()
                Button("New Scale…") { ui.definitionEditor = .new(.scale) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Chord…") { ui.definitionEditor = .new(.chord) }
                    .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            }
            
            // Undo and Redo act on what you're working on: text being typed, the open sequence, or the open tab
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { undoOrRedo(redo: false) }
                    .keyboardShortcut("z", modifiers: [.command])
                Button("Redo") { undoOrRedo(redo: true) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                if ui.tab == .Tab {
                    Button("Save") {
                        if tabSession.fileURL == nil {
                            ui.savePanel = .tab
                        } else {
                            do { try tabSession.save() } catch { ui.errorMessage = error.localizedDescription }
                        }
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!tabSession.isOpen)
                    Button("Save As…") { ui.savePanel = .tab }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(!tabSession.isOpen)
                    Button("Export as Guitar Pro…") { ui.savePanel = .guitarPro }
                        .disabled(!tabSession.isOpen)
                } else {
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
            }
            
            CommandGroup(replacing: .importExport) {
                Button("Import Library…") { ui.isImporting = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export Library…") { ui.isChoosingExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            
            CommandMenu("Playback") {
                Button(transport.isPlaying ? "Stop Playing" : (ui.tab == .Tab ? "Play from Start (Space)" : "Play from 1.1.1 (Space)")) {
                    TransportActions.playPause(ui: ui, session: session, tab: tabSession, playback: playback)
                }
                .keyboardShortcut("p", modifiers: [.command])
                // ⌥Space does this too (handled with the space bar, so it isn't listed here)
                Button(ui.tab == .Tab ? "Play from Cursor (⌥Space)" : "Play from Playhead (⌥Space)") {
                    TransportActions.playSelection(ui: ui, session: session, tab: tabSession, playback: playback)
                }
                .disabled(ui.tab == .Tab ? !tabSession.isOpen : (ui.tab != .Sequence || !session.isOpen))
                Button(session.sequence?.loop == nil ? "Loop" : "Stop Looping") {
                    TransportActions.toggleLoop(ui: ui, session: session, tab: tabSession)
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!(ui.tab == .Sequence && session.isOpen) && !(ui.tab == .Tab && tabSession.linkedSequence != nil))
                Button("Stop") {
                    TransportActions.stop(ui: ui, session: session, tab: tabSession, playback: playback)
                }
                .keyboardShortcut(".", modifiers: [.command])
                Button("Back to Start") {
                    TransportActions.toStart(ui: ui, session: session, tab: tabSession, playback: playback)
                }
                Button(transport.isMetronomeOn ? "Metronome Off" : "Metronome On") { transport.isMetronomeOn.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Preview Shape") { previewCurrentShape() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(ui.tab != .Library)
            }
            
            CommandGroup(before: .toolbar) {
                Button(ui.tab == .Tab ? (ui.isFretboardOnly ? "Show Fretboard" : "Tab Only")
                                      : (ui.isFretboardOnly ? "Show Panel Below Fretboard" : "Fretboard Only")) { ui.isFretboardOnly.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(ui.tab == .Settings)
                Divider()
                Button("Zoom In") { ui.tab == .Tab ? tabSession.editor?.zoom(by: 1.25) : session.editor?.zoom(by: 1.5) }
                    .keyboardShortcut("=", modifiers: [.command])
                    .disabled(ui.tab == .Tab ? !tabSession.isOpen : (ui.tab != .Sequence || !session.isOpen))
                Button("Zoom Out") { ui.tab == .Tab ? tabSession.editor?.zoom(by: 1 / 1.25) : session.editor?.zoom(by: 1 / 1.5) }
                    .keyboardShortcut("-", modifiers: [.command])
                    .disabled(ui.tab == .Tab ? !tabSession.isOpen : (ui.tab != .Sequence || !session.isOpen))
                Toggle("Follow Playhead", isOn: Binding(get: { session.editor?.followsPlayhead ?? false },
                                                        set: { session.editor?.followsPlayhead = $0 }))
                    .disabled(!session.isOpen)
                Divider()
                
                // How the Sequence tab shows each chord's scale on the neck
                Picker("Sequence Neck", selection: Binding(get: { session.editor?.neckView ?? .followHand },
                                                           set: { session.editor?.neckView = $0 })) {
                    Text("Follow Hand").tag(SequenceEditorState.NeckView.followHand)
                    Text("Whole Neck").tag(SequenceEditorState.NeckView.wholeNeck)
                }
                .disabled(!session.isOpen)
                Picker("Start Around Fret", selection: Binding(get: { session.editor?.handFret ?? 5 },
                                                               set: { session.editor?.handFret = $0 })) {
                    ForEach([1, 3, 5, 7, 9, 12], id: \.self) { fret in
                        Text("Fret \(fret)").tag(fret)
                    }
                }
                .disabled(!session.isOpen || session.editor?.neckView != .followHand)
                Toggle("Next Scale on Fretboard", isOn: Binding(get: { session.editor?.showsNextScale ?? true },
                                                                set: { session.editor?.showsNextScale = $0 }))
                    .disabled(!session.isOpen)
                // The next chord box is off for now (see PerformanceHeader)
                // Toggle("Next Chord Box", isOn: Binding(get: { session.editor?.showsNextDiagram ?? false },
                //                                        set: { session.editor?.showsNextDiagram = $0 }))
                //     .disabled(!session.isOpen)
                Picker("Next Chord Brightens", selection: Binding(get: { session.editor?.ghostBeats ?? 2 },
                                                             set: { session.editor?.ghostBeats = $0 })) {
                    Text("1 Beat Early").tag(1.0)
                    Text("2 Beats Early").tag(2.0)
                    Text("1 Bar Early").tag(Double(session.sequence?.beatsPerBar ?? 4))
                }
                .disabled(!session.isOpen)
                Divider()
            }
            
            CommandMenu("Shape") {
                Button(ui.tab == .Library ? "Next Shape" : "Next Voicing") {
                    switch ui.tab {
                    case .Sequence: session.cycleVoicing(by: 1)
                    default: selection.nextShape()
                    }
                }
                .keyboardShortcut("]", modifiers: [.command])
                Button(ui.tab == .Library ? "Previous Shape" : "Previous Voicing") {
                    switch ui.tab {
                    case .Sequence: session.cycleVoicing(by: -1)
                    default: selection.previousShape()
                    }
                }
                .keyboardShortcut("[", modifiers: [.command])
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
                // ⌘L loops
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
       }
    }
    
    private func undoOrRedo(redo: Bool) {
        let isTyping = NSApp.keyWindow?.firstResponder is NSText
        if !isTyping && ui.tab == .Sequence && session.isOpen {
            redo ? session.redo() : session.undo()
        } else if !isTyping && ui.tab == .Tab && tabSession.isOpen {
            redo ? tabSession.redo() : tabSession.undo()
        } else {
            // Text fields (and anything else with its own undo) handle it themselves
            NSApp.sendAction(Selector(redo ? "redo:" : "undo:"), to: nil, from: nil)
        }
    }

    private func previewCurrentShape() {
        guard let shape = selection.currentShape,
              let placement = shape.placements(root: selection.root, on: selection.fretboard).first else { return }
        playback.preview(Audition.events(for: shape, placement: placement, on: selection.fretboard, clock: transport.clock))
    }
}
