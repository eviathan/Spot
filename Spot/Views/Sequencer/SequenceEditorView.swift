//
//  SequenceEditorView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// The Sequence tab with a sequence open: now/next, the chord lane and its controls.
/// The fretboard above is `SequencerFretboard`, and play/tempo are in the main footer.
struct SequenceEditorView: View {
    @Environment(SequenceSession.self) private var session
    
    var body: some View {
        if let editor = session.editor, let sequence = session.sequence {
            let binding = Binding(get: { session.sequence ?? sequence }, set: { session.sequence = $0 })
            VStack(spacing: 0) {
                SequenceFileBar(sequence: binding, editor: editor)
                AudioBar(sequence: binding)
                if sequence.audio != nil && (session.analysisProgress != nil || (session.analysis != nil && session.showsAnalysis)) {
                    AnalysisBar(sequence: sequence)
                }
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

            TextField("Chord", text: $editor.chordText, prompt: Text("Chord, e.g. G7"))
                .frame(width: 130)
                .onSubmit {
                    if editor.applyChord(to: &sequence) {
                        editor.advanceSelection(in: sequence)
                    }
                }
                .help("Type a chord and press Return to set it and move on. Leave empty to clear.")
            
            Button {
                editor.showsPalette.toggle()
            } label: {
                Label("Chords", systemImage: "square.grid.3x3")
            }
            .help("Pick chords without typing (or double-click a bar)")
            .popover(isPresented: $editor.showsPalette, arrowEdge: .top) {
                ChordPalette(key: editor.analysis.key) { symbol in
                    // Set it and move on, keeping the palette open to enter the next chord
                    editor.chordText = symbol
                    if editor.applyChord(to: &sequence) {
                        editor.advanceSelection(in: sequence)
                    }
                }
            }

            Button("Clear") {
                sequence.clearChords(in: editor.selection)
                editor.loadChordText(from: sequence)
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

            Divider().frame(height: 20)

            TextField("Section", text: $editor.sectionName, prompt: Text(section?.name ?? "Section name"))
                .frame(width: 110)
                .onSubmit {
                    let name = editor.sectionName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        sequence.setSection(name, in: editor.selection)
                        editor.sectionName = ""
                    }
                }
            if let section {
                Button("Remove “\(section.name)”") { sequence.removeSection(section.id) }
            }

            Toggle("Loop", isOn: Binding(get: { sequence.loop != nil },
                                         set: { sequence.loop = $0 ? editor.selection : nil }))
                .help("Loop the selected bars")

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
            
            Picker("Time", selection: Binding(get: { sequence.beatsPerBar }, set: { newValue in
                sequence.beatsPerBar = newValue
                editor.snap = Double(newValue)
                editor.select(beat: 0, extend: false, in: sequence)
            })) {
                ForEach([2, 3, 4, 5, 6, 7], id: \.self) { Text("\($0)/4").tag($0) }
            }
            .frame(width: 110)
            .disabled(!sequence.chords.isEmpty)
            .help(sequence.chords.isEmpty ? "Beats per bar" : "Clear the chords to change the time signature")
            
            Stepper(value: Binding(get: { sequence.lengthInBars }, set: { sequence.setLength(bars: $0) }), in: 1...512) {
                Text("\(sequence.lengthInBars) bars")
                    .monospacedDigit()
            }
            
            Picker("Backing", selection: $sequence.backing) {
                Text("Off").tag(BackingStyle.off)
                Text("Pad").tag(BackingStyle.pad)
                Text("Strum").tag(BackingStyle.strum)
                Text("Comp").tag(BackingStyle.comp)
            }
            .frame(width: 160)
            
            Menu {
                Button("Work it out\(sequence.key == nil ? editor.analysis.key.map { " (\($0))" } ?? "" : "")") { sequence.key = nil }
                Divider()
                ForEach([KeyQuality.major, .minor], id: \.self) { quality in
                    Menu(quality == .major ? "Major keys" : "Minor keys") {
                        ForEach(0..<12, id: \.self) { tonic in
                            let key = Key(conventional: PitchClass(tonic), quality)
                            Button(key.description) { sequence.key = key }
                        }
                    }
                }
            } label: {
                Text("Key: \(editor.analysis.key?.description ?? "none")\(sequence.key == nil ? " (auto)" : "")")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Menu("View") {
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
                
                LabeledContent("Speed") {
                    Slider(value: $sequence.practiceRate, in: 0.5...1, step: 0.05)
                        .frame(width: 110)
                    Text("\(Int((sequence.practiceRate * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .help("Practice speed: slows the audio and the backing together without changing pitch")
                
                Button("Tap tempo") { session.tapTempo() }
                    .help("Tap along with the beat; after four taps the tempo is set to match")
                
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
                    Button("Show Analysis") { session.showsAnalysis = true }
                        .disabled(session.analysis == nil || session.showsAnalysis)
                    Button("Analyse Again") { session.analyseAudio() }
                        .disabled(session.audioStatus != .ready)
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

// MARK: - Analysis

/// What was heard in the recording, and buttons to use it. Nothing changes until one is pressed.
private struct AnalysisBar: View {
    let sequence: ChordSequence
    
    @Environment(SequenceSession.self) private var session
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "ear")
            
            if let progress = session.analysisProgress {
                ProgressView(value: progress).frame(width: 100)
                Text("Listening for tempo, beats and chords…").font(.caption)
            } else if let analysis = session.analysis {
                Menu {
                    ForEach(analysis.tempoCandidates, id: \.bpm) { candidate in
                        Button("\(Int(candidate.bpm.rounded())) bpm\(candidate.confidence < 0.999 ? " (\(Int(candidate.confidence * 100))%)" : "")") {
                            session.useAnalysedTempo(candidate.bpm)
                        }
                    }
                } label: {
                    Text("Heard \(String(format: "%.1f", analysis.tempo)) bpm")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("If this is double or half the real tempo, pick another")
                
                HStack(spacing: 4) {
                    Button { session.shiftAnalysedBarOne(by: -1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                    Text(analysis.beats.indices.contains(analysis.downbeat)
                         ? "Bar 1 at \(String(format: "%.2f", analysis.beats[analysis.downbeat])) s" : "Bar 1 ?")
                        .monospacedDigit()
                    Button { session.shiftAnalysedBarOne(by: 1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                }
                .help("Move bar 1 a beat earlier or later if it's on the wrong beat (the ticks on the waveform show the beats heard)")
                
                if let key = analysis.key {
                    Button("Key: \(key.description)") { session.applyAnalysedKey() }
                        .help(sequence.key == key ? "Already the sequence's key" : "Use this key")
                        .disabled(sequence.key == key)
                }
                
                Divider().frame(height: 18)
                
                Button("Apply beat grid") { session.applyAnalysedBeatGrid() }
                    .help("Set the tempo and put a warp marker on every bar so the grid follows the recording")
                
                let chordCount = analysis.chordRegions(key: nil).count
                Menu("Add \(chordCount) chords") {
                    Button("Replace all chords") { session.applyAnalysedChords(onlyEmpty: false) }
                    Button("Only where there's no chord") { session.applyAnalysedChords(onlyEmpty: true) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(chordCount == 0)
                .help("Chords heard in the recording, snapped to beats. Expect to fix some: click a bar and type over it.")
                
                Spacer()
                Button("Hide") { session.showsAnalysis = false }
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.teal.opacity(0.15))
    }
}
