//
//  SequenceEditorView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// The Sequence tab with a sequence open: now/next, the chord lane and its controls.
/// The fretboard above is `SequencerFretboard`; play, loop, key, tempo and time signature are in the main footer.
struct SequenceEditorView: View {
    @Environment(SequenceSession.self) private var session
    
    var body: some View {
        if let editor = session.editor, let sequence = session.sequence {
            let binding = Binding(get: { session.sequence ?? sequence }, set: { session.sequence = $0 })
            VStack(spacing: 0) {
                SequenceFileBar(sequence: binding, editor: editor)
                AudioBar(sequence: binding)
                NowNextView(sequence: sequence, editor: editor)
                ChordLaneView(sequence: sequence, editor: editor)
                Divider()
                LaneEditorBar(sequence: binding, editor: editor)
            }
        }
    }
}

// MARK: - Editing

private struct LaneEditorBar: View {
    @Binding var sequence: ChordSequence
    let editor: SequenceEditorState

    var body: some View {
        @Bindable var editor = editor
        let region = sequence.chord(at: editor.selection.start)
        let section = sequence.section(at: editor.selection.start)

        HStack(spacing: 14) {
            Text(editor.describe(editor.selection, beatsPerBar: sequence.beatsPerBar))
                .font(.headline)
                .frame(width: 110, alignment: .leading)

            Button {
                editor.showsPalette.toggle()
            } label: {
                Label("Chords", systemImage: "square.grid.3x3")
            }
            .help("Pick chords without typing (or double-click a bar)")
            .popover(isPresented: $editor.showsPalette, arrowEdge: .top) {
                ChordPalette(key: editor.analysis.key) { symbol in
                    // Set it and move on, keeping the palette open to enter the next chord
                    if editor.applyChord(symbol, to: &sequence) {
                        editor.advanceSelection(in: sequence)
                    }
                }
            }

            Button("Clear") {
                sequence.clearChords(in: editor.selection)
            }

            if let region, let suggestions = editor.analysis.suggestions[region.id] {
                Picker("Scale", selection: Binding(get: { region.scaleId ?? "" },
                                                   set: { sequence.update(region.id, scaleId: .some($0.isEmpty ? nil : $0)) })) {
                    Text("Auto (\(suggestions.first?.scale.name ?? "none"))").tag("")
                    ForEach(suggestions.prefix(12)) { suggestion in
                        Text(suggestion.scale.name).tag(suggestion.scale.id)
                    }
                }
                .frame(maxWidth: 260)
            }

            if let section {
                Divider().frame(height: 20)
                Button("Remove Section “\(section.name)”") { sequence.removeSection(section.id) }
            }

            Divider().frame(height: 20)

            Picker("Snap", selection: $editor.snap) {
                Text("Bar").tag(Double(sequence.beatsPerBar))
                if sequence.beatsPerBar % 2 == 0 {
                    Text("Half bar").tag(Double(sequence.beatsPerBar) / 2)
                }
                Text("Beat").tag(1.0)
                Text("1/8").tag(0.5)
                Text("1/16").tag(0.25)
                Divider()
                Text("Off").tag(0.0)
            }
            .frame(width: 140)
            .help("The grid for selecting, moving and resizing chords. Chords also stick to each other's edges; hold ⌥ while dragging to ignore both.")

            if let error = editor.chordError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - File and settings

private struct SequenceFileBar: View {
    @Binding var sequence: ChordSequence
    let editor: SequenceEditorState
    
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui
    
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Image(systemName: "music.note.list")
                Text(session.displayName)
                    .font(.headline)
                if session.hasUnsavedChanges && session.fileURL == nil {
                    Text("not saved")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let error = session.saveError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Button(session.fileURL == nil ? "Save…" : "Save As…") { ui.isSavingSequenceAs = true }
            Button("Close") { ui.requestSequenceAction(.close, session: session) }
            
            Divider().frame(height: 20)
            
            Stepper(value: Binding(get: { sequence.lengthInBars }, set: { sequence.setLength(bars: $0) }), in: 1...512) {
                Text("\(sequence.lengthInBars) bars")
                    .monospacedDigit()
            }
            
            Menu("View") {
                Toggle("Follow Playhead", isOn: Binding(get: { editor.followsPlayhead }, set: { editor.followsPlayhead = $0 }))
                Divider()
                Picker("Neck", selection: Binding(get: { editor.neckView }, set: { editor.neckView = $0 })) {
                    Text("Follow Hand").tag(SequenceEditorState.NeckView.followHand)
                    Text("Whole Neck").tag(SequenceEditorState.NeckView.wholeNeck)
                }
                .pickerStyle(.inline)
                Menu("Start Around Fret \(editor.handFret)") {
                    ForEach([1, 3, 5, 7, 9, 12], id: \.self) { fret in
                        Button("Fret \(fret)") { editor.handFret = fret }
                    }
                }
                .disabled(editor.neckView != .followHand)
                Divider()
                Toggle("Next Chord Box", isOn: Binding(get: { editor.showsNextDiagram }, set: { editor.showsNextDiagram = $0 }))
                Picker("Show Next Chord", selection: Binding(get: { editor.ghostBeats }, set: { editor.ghostBeats = $0 })) {
                    Text("1 Beat Early").tag(1.0)
                    Text("2 Beats Early").tag(2.0)
                    Text("1 Bar Early").tag(Double(sequence.beatsPerBar))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Follow Hand shows one position per chord, each close to the last; click a fret to move your hand there")
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hue: 0.63, saturation: 0.30, brightness: 0.20, opacity: 1.00))
    }
}

// MARK: - Audio

private struct AudioBar: View {
    @Binding var sequence: ChordSequence
    
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui
    
    var body: some View {
        HStack(spacing: 16) {
            if session.isRecording {
                Label("Recording", systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .font(.callout.weight(.semibold))
            }
            Image(systemName: "waveform")
            
            if let audio = sequence.audio {
                Text(audio.reference.fileName)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                status(audio)
                
                Divider().frame(height: 18)
                
                Toggle(isOn: Binding(get: { !(sequence.audio?.isMuted ?? false) }, set: { sequence.audio?.isMuted = !$0 })) {
                    Image(systemName: audio.isMuted ? "speaker.slash" : "speaker.wave.2")
                }
                .toggleStyle(.button)
                .help("Mute the recording")
                
                Slider(value: Binding(get: { sequence.audio?.gain ?? 0 }, set: { sequence.audio?.gain = $0 }), in: -24...6)
                    .frame(width: 90)
                    .help("Recording level (dB)")
                
                Menu("Audio") {
                    Button("Clear Warp Markers") { sequence.audio?.removeAllMarkers() }
                        .disabled(audio.warpMarkers.isEmpty)
                    Button("Locate File…") { ui.isRelinkingAudio = true }
                    Button("Replace Audio…") { ui.isImportingAudio = true }
                    Divider()
                    Button("Remove Audio", role: .destructive) { session.removeAudio() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                if audio.warpMarkers.isEmpty && session.audioStatus == .ready {
                    Text("Double-click a hit in the waveform to add a warp marker, then drag it onto its beat.")
                        .font(.caption)
                        .opacity(0.6)
                }
            } else {
                Button("Add Audio…") { ui.isImportingAudio = true }
                Text("Play along with a recording: it stays where it is and is lined up with the grid.")
                    .font(.caption)
                    .opacity(0.6)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func status(_ audio: AudioTrack) -> some View {
        switch session.audioStatus {
        case .loading:
            ProgressView().controlSize(.small)
            Text("Loading…").font(.caption)
        case .missing:
            Label("File not found", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
            Button("Locate…") { ui.isRelinkingAudio = true }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
                .lineLimit(1)
        case .ready, .none:
            if let progress = session.renderProgress {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("Lining up…").font(.caption)
            } else if let warning = session.audioWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}
