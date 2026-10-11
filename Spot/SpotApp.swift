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
    @State private var themes = ThemeStore.shared

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        OverlayScrollers.install()
        MouseButtons.install()

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
                .environment(themes)
                // The theme in use: switching it redraws everything
                .environment(\.theme, themes.current)
                .toolbar {
                    Color.clear
                }
                // In macOS full screen the (empty) toolbar would stay as a grey strip across the top: hidden there,
                // with the header, so Spot fills the screen
                .toolbar(ui.isWindowFullScreen ? .hidden : .visible, for: .windowToolbar)
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
                    Button(tabSession.isSequenceTab ? "Open Tab into Sequence…" : "Open Tab…") { ui.requestTabAction(.open, session: tabSession) }
                        .keyboardShortcut("o", modifiers: [.command])
                    Menu("Open Recent") {
                        ForEach(tabSession.recents) { recent in
                            Button(recent.name) { ui.requestTabAction(.openRecent(recent), session: tabSession) }
                        }
                    }
                    .disabled(tabSession.recents.isEmpty)
                    Button("Close Tab") { ui.requestTabAction(.close, session: tabSession) }
                        .disabled(!tabSession.isOpen || tabSession.isSequenceTab)
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
            
            // (Grouped: a commands block takes ten at most)
            Group {
                // Settings is a tab of the window, not a window of its own: ⌘, goes to it, as in any Mac app
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { ui.tab = .Settings }
                        .keyboardShortcut(",", modifiers: [.command])
                }
                // Undo and Redo act on what you're working on: text being typed, the open sequence, or the open tab
                CommandGroup(replacing: .undoRedo) {
                    Button("Undo") { undoOrRedo(redo: false) }
                        .keyboardShortcut("z", modifiers: [.command])
                    Button("Redo") { undoOrRedo(redo: true) }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                }
            }

            CommandGroup(replacing: .saveItem) {
                if ui.tab == .Tab && tabSession.isSequenceTab {
                    // The sequence's tab is saved with the sequence; it can also be written out on its own
                    Button("Save Sequence") {
                        if session.fileURL == nil {
                            ui.isSavingSequenceAs = true
                        } else {
                            do { try session.save() } catch { ui.errorMessage = error.localizedDescription }
                        }
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                    Button("Export Tab…") { ui.savePanel = .tab }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                    Button("Export as Guitar Pro…") { ui.savePanel = .guitarPro }
                    Divider()
                    Button("Export Tab as PDF…") { ui.savePanel = .tabPDF }
                    Button("Print Tab…") { tabSession.printContent.map(TabPrinter.print) }
                } else if ui.tab == .Tab {
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
                    Divider()
                    Button("Export Tab as PDF…") { ui.savePanel = .tabPDF }
                        .disabled(!tabSession.isOpen)
                    Button("Print Tab…") { tabSession.printContent.map(TabPrinter.print) }
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
            
            // Patterns: chords grouped to repeat, and placed again linked
            CommandMenu("Pattern") {
                // Only on the Sequence tab: not enabled by the selection, which the menu bar would then be rebuilt
                // for on every mouse movement of a drag (the commands do nothing where they don't apply)
                let onSequence = ui.tab == .Sequence && session.isOpen
                Button("Group Selection") { session.groupSelection() }
                    .keyboardShortcut("g", modifiers: [.command])
                    .disabled(!onSequence)
                Button("Ungroup") { session.ungroupPattern() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!onSequence)
                Divider()
                Button("Duplicate") { session.duplicatePattern() }
                    .keyboardShortcut("d", modifiers: [.command])
                    .disabled(!onSequence)
                Button("Make Unique") { session.makePatternUnique() }
                    .disabled(!onSequence)
                Button("Delete Pattern") { session.deletePattern() }
                    .disabled(!onSequence)
                Button("Rename…") { session.editor?.renamingPattern = session.selectedPattern?.pattern.id }
                    .disabled(!onSequence)
            }

            // The sequencer's grid, with Live's shortcuts
            CommandMenu("Grid") {
                let editor = session.editor
                let enabled = ui.tab == .Sequence && editor != nil
                Button("Narrow Grid") { editor?.narrowGrid() }
                    .keyboardShortcut("1", modifiers: [.command])
                    .disabled(!enabled)
                Button("Widen Grid") { editor?.widenGrid() }
                    .keyboardShortcut("2", modifiers: [.command])
                    .disabled(!enabled)
                Button(editor?.isTripletGrid == true ? "Straight Grid" : "Triplet Grid") { editor?.isTripletGrid.toggle() }
                    .keyboardShortcut("3", modifiers: [.command])
                    .disabled(!enabled)
                Button(editor?.grid == .off ? "Snap to Grid" : "Don't Snap to Grid") { editor?.toggleSnap() }
                    .keyboardShortcut("4", modifiers: [.command])
                    .disabled(!enabled)
                Divider()
                Button(editor.map { if case .adaptive = $0.grid { return "Fixed Grid" } else { return "Adaptive Grid" } } ?? "Adaptive Grid") {
                    guard let editor else { return }
                    if case .adaptive = editor.grid {
                        // The fixed grid nearest what the adaptive one is now
                        let now = editor.snap
                        let signature = session.sequence?.timeSignature ?? TimeSignature(4, 4)
                        editor.grid = GridMode.fixed(timeSignature: signature)
                            .min { abs($0.beats(timeSignature: signature, beatWidth: 1, triplet: editor.isTripletGrid) - now)
                                 < abs($1.beats(timeSignature: signature, beatWidth: 1, triplet: editor.isTripletGrid) - now) } ?? .note(1)
                    } else {
                        editor.grid = .adaptive(.medium)
                    }
                }
                .disabled(!enabled)
            }

            CommandMenu("Playback") {
                // From any page, like the transport (see TransportActions.target)
                let target = TransportActions.target(ui: ui, session: session, tab: tabSession)
                Button(transport.isPlaying ? "Stop Playing" : (target == .tab ? "Play from Start (Space)" : "Play from 1.1.1 (Space)")) {
                    TransportActions.playPause(ui: ui, session: session, tab: tabSession, playback: playback)
                }
                .keyboardShortcut("p", modifiers: [.command])
                // ⌥Space does this too (handled with the space bar, so it isn't listed here)
                Button(ui.tab == .Tab && target != .metronome ? "Play from Cursor (⌥Space)" : "Play from Playhead (⌥Space)") {
                    TransportActions.playSelection(ui: ui, session: session, tab: tabSession, playback: playback)
                }
                .disabled(target == .metronome)
                Button(session.isLooping ? "Stop Looping" : "Loop") {
                    TransportActions.toggleLoop(ui: ui, session: session, tab: tabSession)
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(target != .sequence)
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
                Toggle("Next Scale on Fretboard", isOn: Binding(get: { session.editor?.showsNextScale ?? false },
                                                                set: { session.editor?.showsNextScale = $0 }))
                    .disabled(!session.isOpen)
                // The next chord box is off for now (see PerformanceHeader)
                // Toggle("Next Chord Box", isOn: Binding(get: { session.editor?.showsNextDiagram ?? false },
                //                                        set: { session.editor?.showsNextDiagram = $0 }))
                //     .disabled(!session.isOpen)
                Picker("Next Chord Shows", selection: Binding(get: { session.editor?.ghostBeats },
                                                         set: { session.editor?.ghostBeats = $0 })) {
                    Text("1 Beat Early").tag(Double?.some(1))
                    Text("2 Beats Early").tag(Double?.some(2))
                    Text("1 Bar Early").tag(Double?.none)
                    Text("2 Bars Early").tag(Double?.some(session.barLength * 2))
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
                    // (Notes fade and grow or shrink between the two, rather than jumping)
                    withAnimation(.easeInOut(duration: 0.3)) { display.hideUnrelatedNotes.toggle() }
                }
                .keyboardShortcut("U", modifiers: [.command])
                Button("Toggle Shape Isolation") {
                    // (Notes fade and grow or shrink between the two, rather than jumping)
                    withAnimation(.easeInOut(duration: 0.3)) { display.isolatePosition.toggle() }
                }
                .keyboardShortcut("I", modifiers: [.command])
                Button("Toggle Highlight All Shapes") {
                    // (Notes fade and grow or shrink between the two, rather than jumping)
                    withAnimation(.easeInOut(duration: 0.3)) { display.highlightAllPositions.toggle() }
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
