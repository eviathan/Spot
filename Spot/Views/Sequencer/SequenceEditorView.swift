//
//  SequenceEditorView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// The Sequence tab with a sequence open: now/next, the chord lane and its controls.
/// The fretboard above is `SequencerFretboard`; play, loop, key, tempo and time signature are in the main footer,
/// and file and view options in the menu bar.
struct SequenceEditorView: View {
    @Environment(SequenceSession.self) private var session
    
    var body: some View {
        if let editor = session.editor, let sequence = session.sequence {
            let binding = Binding(get: { session.sequence ?? sequence }, set: { session.sequence = $0 })
            VStack(spacing: 0) {
                AudioBar(sequence: binding, editor: editor)
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
                // The selected range, or the chord at the playhead
                let range = editor.selection.length > 0 ? editor.selection : sequence.chord(at: editor.selection.start)?.range
                if let range { sequence.clearChords(in: range) }
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

// MARK: - Now, next and the recording

/// One row: the chord now and the beat, what's next, which sequence, then the recording's tempos and level.
private struct AudioBar: View {
    @Binding var sequence: ChordSequence
    let editor: SequenceEditorState
    
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui
    
    var body: some View {
        HStack(spacing: 14) {
            NowNextView(sequence: sequence, editor: editor)
            
            Spacer(minLength: 8)
            
            // Which sequence (Save, Close and the rest are in the File menu)
            HStack(spacing: 5) {
                Image(systemName: "music.note.list")
                Text(session.displayName)
                    .lineLimit(1)
                if session.hasUnsavedChanges && session.fileURL == nil {
                    Text("not saved")
                        .foregroundStyle(.orange)
                } else if let error = session.saveError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help(error)
                }
            }
            .font(.caption)
            .opacity(0.8)
            
            Divider().frame(height: 18)
            
            if session.isRecording {
                Label("Recording", systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .font(.callout.weight(.semibold))
            }
            
            if let audio = sequence.audio {
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                    Text(audio.reference.fileName)
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                }
                .font(.callout)
                .help("Double-click the waveform to add a warp marker, drag a marker onto its beat (⇧ to slide it along the audio instead)")
                status(audio)
                
                RecordingTempo(sequence: $sequence, editor: editor)
                
                Toggle(isOn: Binding(get: { !(sequence.audio?.isMuted ?? false) }, set: { sequence.audio?.isMuted = !$0 })) {
                    Image(systemName: audio.isMuted ? "speaker.slash" : "speaker.wave.2")
                }
                .toggleStyle(.button)
                .help(audio.isMuted ? "The recording is muted: click to hear it" : "Mute the recording")
                
                Slider(value: Binding(get: { sequence.audio?.gain ?? 0 }, set: { sequence.audio?.gain = $0 }), in: -24...6)
                    .frame(width: 90)
                    .help("Recording level (dB)")
                
                Menu("Audio") {
                    Button("Clear Warp Markers") { sequence.audio?.removeAllMarkers() }
                        .disabled(audio.warpMarkers.count <= 1)
                    Button("Locate File…") { ui.isRelinkingAudio = true }
                    Button("Replace Audio…") { ui.isImportingAudio = true }
                    Divider()
                    Button("Remove Audio", role: .destructive) { session.removeAudio() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Button("Add Audio…") { ui.isImportingAudio = true }
                    .help("Play along with a recording: it stays where it is and is lined up with the grid")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func status(_ audio: AudioTrack) -> some View {
        switch session.audioStatus {
        case .loading:
            ProgressView().controlSize(.small)
        case .missing:
            Label("File not found", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
            Button("Locate…") { ui.isRelinkingAudio = true }
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(message)
        case .ready, .none:
            if let warning = session.audioWarning {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(warning)
            }
        }
    }
}

/// The recording's own tempo where the playhead is (between two markers, that section's) and the tempo
/// it's playing at, like Seg. BPM in Live. Drag the number to change it (⌥ for tenths), double-click to
/// type it, or tap along.
private struct RecordingTempo: View {
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
        
        HStack(spacing: 6) {
            Text(isSection ? "Section" : "Original")
                .font(.caption)
                .opacity(0.6)
            Text(String(format: "%.1f", original))
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
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
                .font(.caption)
                .opacity(0.6)
            Text("\(Int(sequence.tempo.rounded()))")
                .font(.system(.body, design: .monospaced))
                .help("The tempo it's playing at (in the footer)")
            Button {
                session.tapRecordingTempo(atBeat: beat)
            } label: {
                Image(systemName: "hand.tap")
            }
            .buttonStyle(.plain)
            .help("Tap along with the recording to set its own tempo here (after four taps)")
        }
        .help(isSection
              ? "The tempo of the recording between the warp markers around the playhead. Drag to change it (⌥ for tenths), double-click to type it."
              : "The tempo the recording was played at. Drag to change it (⌥ for tenths), double-click to type it.")
    }
    
    private func setTempo(_ bpm: Double) {
        sequence.audio?.setSegmentTempo((bpm * 10).rounded() / 10, atBeat: beat)
    }
}
