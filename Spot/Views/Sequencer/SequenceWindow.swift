//
//  SequenceWindow.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Lets menu commands act on the focused sequence window.
struct SequenceActions {
    var togglePlay: () -> Void
}

struct SequenceActionsKey: FocusedValueKey {
    typealias Value = SequenceActions
}

extension FocusedValues {
    var sequenceActions: SequenceActions? {
        get { self[SequenceActionsKey.self] }
        set { self[SequenceActionsKey.self] = newValue }
    }
}

/// A `.spot` document's window: fretboard, now/next, the chord lane and its controls.
struct SequenceWindow: View {
    @Binding var document: SequenceDocument

    @State private var editor: SequenceEditorState

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport

    let background = Color(hue: 0.62, saturation: 0.38, brightness: 0.24, opacity: 1.00)

    init(document: Binding<SequenceDocument>, library: LibraryStore) {
        _document = document
        _editor = State(initialValue: SequenceEditorState(library: library))
    }

    private var isPlaying: Bool {
        playback.playingSequence == editor.id
    }

    var body: some View {
        VStack(spacing: 0) {
            SequencerFretboard(sequence: document.sequence, editor: editor)
                .frame(height: 230)
            NowNextView(sequence: document.sequence, editor: editor)
            ChordLaneView(sequence: document.sequence, editor: editor)
            Divider()
            LaneEditorBar(sequence: $document.sequence, editor: editor)
            SequenceTransportBar(sequence: $document.sequence, editor: editor, togglePlay: togglePlay)
        }
        .foregroundColor(.white)
        .background(background)
        .frame(minWidth: 1100, minHeight: 640)
        .focusedSceneValue(\.sequenceActions, SequenceActions(togglePlay: togglePlay))
        .onAppear {
            editor.analyse(document.sequence)
            editor.snap = Double(document.sequence.beatsPerBar)
            editor.select(beat: 0, extend: false, in: document.sequence)
        }
        .onChange(of: document.sequence) { _, sequence in
            editor.analyse(sequence)
            if isPlaying {
                playback.update(editor.playback(for: sequence), id: editor.id)
                transport.setBPM(Int(sequence.tempo.rounded()))
            }
        }
        .onDisappear {
            if isPlaying { playback.stop() }
        }
    }

    private func togglePlay() {
        if isPlaying {
            playback.stop()
        } else {
            transport.setBPM(Int(document.sequence.tempo.rounded()))
            transport.beatsPerBar = document.sequence.beatsPerBar
            playback.play(editor.playback(for: document.sequence), from: editor.selection.start, id: editor.id)
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
            }
            .frame(width: 140)

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

// MARK: - Transport

private struct SequenceTransportBar: View {
    @Binding var sequence: ChordSequence
    let editor: SequenceEditorState
    let togglePlay: () -> Void

    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport

    var body: some View {
        @Bindable var transport = transport
        let isPlaying = playback.playingSequence == editor.id

        HStack(spacing: 18) {
            Button(action: togglePlay) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help("Play from the selection (⌘P)")

            Toggle(isOn: $transport.isMetronomeOn) {
                Image(systemName: "metronome")
            }
            .toggleStyle(.button)
            .help("Metronome")

            Stepper(value: $sequence.tempo, in: 20...300, step: 1) {
                Text("\(Int(sequence.tempo)) bpm")
                    .monospacedDigit()
            }

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

            Picker("Show next chord", selection: Binding(get: { editor.ghostBeats }, set: { editor.ghostBeats = $0 })) {
                Text("1 beat early").tag(1.0)
                Text("2 beats early").tag(2.0)
                Text("1 bar early").tag(Double(sequence.beatsPerBar))
            }
            .frame(width: 260)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }
}
