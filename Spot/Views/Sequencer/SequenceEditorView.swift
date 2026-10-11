//
//  SequenceEditorView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// The Sequence tab with a sequence open, under the fretboard (`SequencerFretboard`):
/// - what's playing: the chord now, its chord and scale intervals, and the next chord (`PerformanceHeader`)
/// - the lane, with a header for each row on its left (the recording's controls sit beside its waveform)
/// - tools for the selection, and which sequence this is
/// Play, loop, key, tempo and time signature are in the main footer; file and view options in the menu bar.
struct SequenceEditorView: View {
    @Environment(SequenceSession.self) private var session

    var body: some View {
        if let sequence = session.sequence, session.isPreparingAudio {
            AudioLoadingView(fileName: sequence.audio?.reference.fileName)
        } else if let editor = session.editor, let sequence = session.sequence {
            let binding = Binding(get: { session.sequence ?? sequence }, set: { session.sequence = $0 })
            VStack(spacing: 0) {
                PerformanceHeader(sequence: sequence, editor: editor)
                Divider()
                ChordLaneView(sequence: sequence, editor: editor)
                Divider()
                LaneEditorBar(sequence: binding, editor: editor)
            }
        }
    }
}

/// Nothing to work with until the recording can be heard: just what's happening. (The Sequence and Tab tabs.)
struct AudioLoadingView: View {
    let fileName: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                // White: the macOS spinner takes its colour from the appearance, not a tint
                .tint(.white)
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 12)
            Text("Loading \(fileName ?? "audio")…")
                .font(.title3)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// How wide the column of row headers to the left of the lane is.
let laneHeaderWidth: CGFloat = 196

// MARK: - Editing

/// Tools for the selection on the left; the sequence's name and whether it's saved on the right.
private struct LaneEditorBar: View {
    @Binding var sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(SequenceSession.self) private var session
    @Environment(TabSession.self) private var tabSession
    @Environment(UIState.self) private var ui
    @State private var unreadableChords: [String]?

    var body: some View {
        @Bindable var editor = editor
        let region = sequence.chord(at: editor.selection.start)
        let section = sequence.section(at: editor.selection.start)

        HStack(spacing: 12) {
            Text(editor.describe(editor.selection, in: sequence))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
                .help("The playhead, or the selected range")

            // Plain buttons, white on the bar's colour
            Button {
                editor.showsPalette.toggle()
            } label: {
                Label("Chords", systemImage: "square.grid.3x3")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
            .help("Pick a chord for the selection (or double-click in the lane)")
            .popover(isPresented: $editor.showsPalette, arrowEdge: .top) {
                // Changing a chord (e.g. double-clicked): it's highlighted in the palette
                ChordPalette(key: editor.analysis.key,
                             current: sequence.chord(at: editor.selection.start).flatMap { editor.analysis.chords[$0.id] }) { symbol in
                    // Set it and move on, keeping the palette open to enter the next chord
                    if editor.applyChord(symbol, to: &sequence) {
                        editor.advanceSelection(in: sequence)
                    }
                }
            }

            // Only when there are chords in the selection to clear
            if editor.selection.length > 0, sequence.chords.contains(where: { $0.range.overlaps(editor.selection) }) {
                Button {
                    sequence.clearChords(in: editor.selection)
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderless)
                .help("Remove the chords in the selection")
            }

            if let region, let suggestions = editor.analysis.suggestions[region.id] {
                let inUse = editor.analysis.scales[region.id]?.name ?? "None"
                BarMenu(title: "Scale", value: inUse, isPinned: region.scaleId != nil,
                        help: region.scaleId == nil
                            ? "Scale: \(inUse), the best fit for this chord. Pick another to use it instead."
                            : "Scale: \(inUse), picked for this chord (the pin). Choose Automatic to go back to the best fit.") {
                    choice("Automatic (\(suggestions.first?.scale.name ?? "none"))", region.scaleId == nil) {
                        sequence.update(region.id, scaleId: .some(nil))
                    }
                    Divider()
                    // The scale in use is ticked, whether picked or automatic
                    ForEach(suggestions.prefix(12)) { suggestion in
                        choice(suggestion.scale.name, editor.analysis.scales[region.id]?.id == suggestion.scale.id) {
                            sequence.update(region.id, scaleId: .some(suggestion.scale.id))
                        }
                    }
                    Divider()
                    // Any scale at all, with its other name, for when the one you want isn't among the matches
                    Menu("All Scales") {
                        ForEach(editor.library.scales.sorted { $0.name < $1.name }) { scale in
                            choice(scale.aliases.first.map { "\(scale.name) (\($0))" } ?? scale.name,
                                   editor.analysis.scales[region.id]?.id == scale.id) {
                                sequence.update(region.id, scaleId: .some(scale.id))
                            }
                        }
                    }
                }
            }

            // How to play this chord, and where to play its scale: chosen automatically, or picked
            if let region, let chord = editor.analysis.chords[region.id] {
                let neck = editor.analysis.positions[region.id]
                shapeMenu(title: "Voicing", options: editor.voicingOptions(for: chord), current: neck?.voicing,
                          picked: region.voicing) { pick in sequence.pick(region.id, voicing: .some(pick)) }
                if let scale = editor.analysis.scales[region.id] {
                    shapeMenu(title: "Position", options: editor.positionOptions(for: chord, scale: scale), current: neck?.position,
                              picked: region.position) { pick in sequence.pick(region.id, position: .some(pick)) }
                }
            }

            if let section {
                Button("Remove Section “\(section.name)”") { sequence.removeSection(section.id) }
            }

            gridMenu
            
            tabMenu

            if let error = editor.chordError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Which sequence (Save, Close and the rest are in the File menu)
            HStack(spacing: 6) {
                if session.isRecording {
                    Label("Recording", systemImage: "record.circle")
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
                Image(systemName: "music.note.list")
                    .opacity(0.6)
                Text(session.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if session.hasUnsavedChanges && session.fileURL == nil {
                    Text("Not saved")
                        .foregroundStyle(.orange)
                } else if let error = session.saveError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help(error)
                }
            }
            .font(.callout)
            .frame(maxWidth: 260, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        // A little more below, to sit level above the footer
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

extension LaneEditorBar {
    /// The grid, as in Live: adaptive (following the zoom, from Narrowest to Widest) or fixed at a note value or
    /// bars, with triplets, or off. ⌘1 / ⌘2 narrow and widen it, ⌘3 triplets, ⌘4 snapping on and off.
    @ViewBuilder
    var gridMenu: some View {
        let grid = editor.grid
        let value: String = {
            switch grid {
            case .off: return "Off"
            case .adaptive: return "Adaptive · \(editor.gridName)"
            default: return editor.gridName
            }
        }()
        BarMenu(title: "Grid", value: value,
                help: "The grid for the playhead, selecting, and moving and resizing chords: adaptive (it follows the zoom) or fixed. ⌘1 narrower, ⌘2 wider, ⌘3 triplets, ⌘4 snap on or off. Chords also stick to each other's edges; hold ⌥ while dragging to ignore both.") {
            Section("Adaptive") {
                ForEach(GridDensity.allCases, id: \.self) { density in
                    choice(density.name, grid == .adaptive(density)) { editor.grid = .adaptive(density) }
                }
            }
            Section("Fixed") {
                ForEach(GridMode.fixed(beatsPerBar: sequence.beatsPerBar).reversed(), id: \.self) { fixed in
                    choice(GridMode.name(beats: fixed.beats(beatsPerBar: Double(sequence.beatsPerBar), beatWidth: 1, triplet: false),
                                         beatsPerBar: Double(sequence.beatsPerBar), triplet: false),
                           grid == fixed) { editor.grid = fixed }
                }
            }
            Divider()
            choice("Triplets", editor.isTripletGrid) { editor.isTripletGrid.toggle() }
            choice("Off", grid == .off) { editor.toggleSnap() }
        }
    }

    /// The sequence's tab: edit it (in the Tab tab), mute it, bring in its chord names.
    @ViewBuilder
    var tabMenu: some View {
        let notes = sequence.tablature.map { score in
            score.tracks.reduce(0) { $0 + $1.bars.reduce(0) { $0 + $1.voices[0].beats.reduce(0) { $0 + $1.notes.count } } }
        } ?? 0
        BarMenu(title: "Tab", value: notes == 0 ? "Empty" : sequence.tabIsMuted ? "Muted" : "\(notes) notes",
                help: "The sequence's tab, written in the Tab tab: it plays along with the sequence, from 1.1.1") {
            Button("Edit in the Tab Tab") { ui.tab = .Tab }
            choice("Mute", sequence.tabIsMuted) { sequence.tabIsMuted.toggle() }
            Divider()
            Button("Use Its Chord Names in the Sequence") {
                let unreadable = session.addChordsFromTablature()
                unreadableChords = unreadable.isEmpty ? nil : unreadable
            }
            .disabled(!session.tablatureHasChords)
        }
        .alert("Some chord names weren't added", isPresented: Binding(get: { unreadableChords != nil },
                                                                      set: { if !$0 { unreadableChords = nil } })) {
            Button("OK") { unreadableChords = nil }
        } message: {
            Text("Spot couldn't read these as chords: \((unreadableChords ?? []).joined(separator: ", ")). The rest were added.")
        }
    }

    /// "bar 3.2" for a beat, counted from the start marker.
    private func barLabel(_ beat: Double) -> String {
        let position = sequence.barAndBeat(at: beat)
        return "bar \(position.bar).\(Int(position.beat) + 1)"
    }

    /// A menu of shapes to choose from, grouped by system and ordered up the neck, with Automatic first.
    /// Its title shows what's in use (picked or not), with its group.
    @ViewBuilder
    func shapeMenu(title: String, options: [SequenceEditorState.ShapeOption], current: SequenceEditorState.ShapeOption?,
                   picked: ShapePick?, choose: @escaping (ShapePick?) -> Void) -> some View {
        let systems = options.reduce(into: [String]()) { if !$0.contains($1.shape.system) { $0.append($1.shape.system) } }
        BarMenu(title: title, value: current?.label ?? "None", isPinned: picked != nil,
                help: picked == nil
                    ? "\(title): \(current?.label ?? "none"), chosen automatically to stay near your hand. Pick one to use it for this chord\(title == "Voicing" ? " (or ⌘[ ⌘] to step through them)" : "")."
                    : "\(title): \(current?.label ?? "none"), picked for this chord (the pin). Choose Automatic to let Spot choose again.") {
            choice("Automatic", picked == nil) {
                choose(nil)
            }
            Divider()
            // The shape in use is ticked (picked or automatic), and so is the group it's in
            ForEach(systems, id: \.self) { system in
                Menu(current?.shape.system == system ? "\(system)  ✓" : system) {
                    ForEach(options.filter { $0.shape.system == system }) { option in
                        choice(option.shortLabel, option.pick == current?.pick) {
                            choose(option.pick)
                        }
                    }
                }
            }
        }
        .disabled(options.isEmpty)
    }

    /// A menu item with a native checkmark when it's the one in use. (A label with a checkmark icon doesn't
    /// reliably show its icon in a macOS menu; a toggle always shows its tick.)
    func choice(_ title: String, _ isOn: Bool, action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action() }))
    }
}

/// A dropdown in the editor bar: a dimmed title, then what's chosen in white (shortened to a set length, with the
/// whole thing in the tooltip), a pin when it was picked by hand, and a chevron. Plain, on the bar's colour.
struct BarMenu<Content: View>: View {
    let title: String
    let value: String
    var isPinned = false
    var help: String
    @ViewBuilder let content: () -> Content

    /// Long names keep their start (the group, e.g. "Open · …") and lose the end.
    static func shortened(_ text: String, to length: Int = 30) -> String {
        text.count <= length ? text : String(text.prefix(length - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .opacity(0.6)
                Text(BarMenu.shortened(value))
                    .fontWeight(.medium)
                    .lineLimit(1)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .opacity(0.8)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        // Plain: the borderless menu style tints its label with the accent colour, whatever colour it's given
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }
}

// MARK: - The recording's row header

/// Beside the waveform: the file, its tempo, mute and level, and the Audio menu; or a way to add one.
struct AudioTrackHeader: View {
    let sequence: ChordSequence
    let editor: SequenceEditorState
    let height: CGFloat

    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui

    var body: some View {
        let binding = Binding(get: { session.sequence ?? sequence }, set: { session.sequence = $0 })

        VStack(alignment: .leading, spacing: 6) {
            if let audio = sequence.audio {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.cyan)
                    Text(audio.reference.fileName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    status
                    Menu {
                        Button("Clear Warp Markers") { session.sequence?.audio?.removeAllMarkers() }
                            .disabled(audio.warpMarkers.count <= 1)
                        Button("Locate File…") { ui.isRelinkingAudio = true }
                        Button("Replace Audio…") { ui.isImportingAudio = true }
                        Divider()
                        Button("Remove Audio", role: .destructive) { session.removeAudio() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Audio")
                }
                .help("Double-click the waveform to add a warp marker and drag it onto its beat. Markers are picked up by their arrows; ⇧-drag one to slide the audio under it.")

                RecordingTempo(sequence: binding, editor: editor)

                HStack(spacing: 6) {
                    Button {
                        session.sequence?.audio?.isMuted.toggle()
                    } label: {
                        Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(audio.isMuted ? .orange : .primary)
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .help(audio.isMuted ? "The recording is muted: click to hear it" : "Mute the recording")

                    Slider(value: Binding(get: { sequence.audio?.gain ?? 0 }, set: { session.sequence?.audio?.gain = $0 }), in: -24...6)
                        .controlSize(.small)
                        .help("Recording level")
                    Text("\(Int(audio.gain.rounded())) dB")
                        .font(.caption.monospacedDigit())
                        .opacity(0.7)
                        .frame(width: 40, alignment: .trailing)
                }
            } else {
                Label("Audio", systemImage: "waveform")
                    .font(.callout.weight(.semibold))
                    .opacity(0.7)
                Button("Add Audio…") { ui.isImportingAudio = true }
                Text("Play along with a recording, lined up with the grid.")
                    .font(.caption)
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: laneHeaderWidth, height: height, alignment: .topLeading)
    }

    @ViewBuilder
    private var status: some View {
        switch session.audioStatus {
        case .loading:
            ProgressView().controlSize(.mini)
        case .missing:
            Button {
                ui.isRelinkingAudio = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("The file can't be found. Click to locate it.")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)
        case .ready, .none:
            if let warning = session.audioWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(warning)
            }
        }
    }
}

/// The recording's own tempo where the playhead is (between two markers, that section's) and the tempo
/// it's playing at, like Seg. BPM in Live. Drag the number to change it (⌥ for tenths), double-click to
/// type it, or tap along.
struct RecordingTempo: View {
    @Binding var sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(SequenceSession.self) private var session
    @State private var dragStart: Double?
    @State private var isTyping = false
    @State private var typed = ""

    private var beat: Double {
        editor.selection.start
    }

    var body: some View {
        let original = sequence.audio?.segmentTempo(atBeat: beat) ?? sequence.tempo
        let isSection = (sequence.audio?.warpMarkers.count ?? 0) > 1 && abs(original - (sequence.audio?.tempo ?? original)) > 0.001

        HStack(spacing: 5) {
            Text(isSection ? "Section" : "Original")
                .font(.caption)
                .opacity(0.6)
            Text(String(format: "%.1f", original))
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? original
                        dragStart = start
                        let step = NSEvent.modifierFlags.contains(.option) ? 0.1 : 1
                        let change = (Double(value.translation.width - value.translation.height) / 4).rounded() * step
                        setTempo(start + change)
                    }
                    .onEnded { _ in dragStart = nil })
                .onTapGesture(count: 2) {
                    typed = String(format: "%.1f", original)
                    isTyping = true
                }
                .popover(isPresented: $isTyping, arrowEdge: .bottom) {
                    TextField("BPM", text: $typed)
                        .frame(width: 80)
                        .padding(10)
                        .onSubmit {
                            if let value = Double(typed.trimmingCharacters(in: .whitespaces)) {
                                setTempo(value)
                            }
                            isTyping = false
                        }
                }
            Image(systemName: "arrow.right")
                .font(.caption2)
                .opacity(0.6)
            Text("\(Int(sequence.tempo.rounded()))")
                .font(.system(.callout, design: .monospaced))
                .help("The tempo it's playing at (in the footer)")
            Spacer(minLength: 0)
            Button {
                session.tapRecordingTempo(atBeat: beat)
            } label: {
                Image(systemName: "hand.tap")
            }
            .buttonStyle(.plain)
            .help("Tap along with the recording to set its own tempo here (after four taps)")
        }
        .help(isSection
              ? "The tempo of the recording between the warp markers around the playhead, then the tempo it's playing at. Drag to change it (⌥ for tenths), double-click to type it."
              : "The tempo the recording was played at, then the tempo it's playing at. Drag to change it (⌥ for tenths), double-click to type it.")
    }

    private func setTempo(_ bpm: Double) {
        sequence.audio?.setSegmentTempo((bpm * 10).rounded() / 10, atBeat: beat)
    }
}
