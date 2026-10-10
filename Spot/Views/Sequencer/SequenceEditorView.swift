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
        if let editor = session.editor, let sequence = session.sequence {
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

/// How wide the column of row headers to the left of the lane is.
let laneHeaderWidth: CGFloat = 196

// MARK: - Editing

/// Tools for the selection on the left; the sequence's name and whether it's saved on the right.
private struct LaneEditorBar: View {
    @Binding var sequence: ChordSequence
    let editor: SequenceEditorState

    @Environment(SequenceSession.self) private var session

    var body: some View {
        @Bindable var editor = editor
        let region = sequence.chord(at: editor.selection.start)
        let section = sequence.section(at: editor.selection.start)

        HStack(spacing: 12) {
            Text(editor.describe(editor.selection, beatsPerBar: sequence.beatsPerBar))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
                .help("The playhead, or the selected range")

            Button {
                editor.showsPalette.toggle()
            } label: {
                Label("Chords", systemImage: "square.grid.3x3")
            }
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

            Button("Clear") {
                // The selected range, or the chord at the playhead
                let range = editor.selection.length > 0 ? editor.selection : sequence.chord(at: editor.selection.start)?.range
                if let range { sequence.clearChords(in: range) }
            }
            .help("Remove the chords in the selection, or the chord at the playhead")

            if let region, let suggestions = editor.analysis.suggestions[region.id] {
                Picker("Scale", selection: Binding(get: { region.scaleId ?? "" },
                                                   set: { sequence.update(region.id, scaleId: .some($0.isEmpty ? nil : $0)) })) {
                    Text("Auto (\(suggestions.first?.scale.name ?? "none"))").tag("")
                    ForEach(suggestions.prefix(12)) { suggestion in
                        Text(suggestion.scale.name).tag(suggestion.scale.id)
                    }
                }
                .frame(maxWidth: 250)
                .help("The scale to play over this chord")
            }

            if let section {
                Button("Remove Section “\(section.name)”") { sequence.removeSection(section.id) }
            }

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
            .fixedSize()
            .help("The grid for the playhead, selecting, and moving and resizing chords. Chords also stick to each other's edges; hold ⌥ while dragging to ignore both.")

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
        .padding(.vertical, 8)
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
                .help("Double-click the waveform to add a warp marker and drag it onto its beat. Markers are picked up by their arrows (⇧ slides one along the audio).")

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
