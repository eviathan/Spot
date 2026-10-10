//
//  ChordPracticeTabView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Pick a chord (or step through a progression) and see what to play over it.
struct ChordPracticeTabView: View {
    @Environment(PracticeState.self) private var practice

    let panelColor = Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00)

    var body: some View {
        VStack(spacing: 0) {
            ProgressionBar()

            if practice.current == nil {
                Text("Type a chord or a progression above, e.g. Dm7 G7 Cmaj7")
                    .opacity(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ScaleSuggestionList()
                        .frame(width: 340)
                        .background(panelColor)
                    ArpeggioList()
                        .frame(width: 280)
                    Divider()
                    PracticeDetail()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Progression

private struct ProgressionBar: View {
    @Environment(PracticeState.self) private var practice
    @State private var replacing: Int?
    @State private var addingChord = false

    let unselectedColor = Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00)

    var body: some View {
        @Bindable var practice = practice

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .imageScale(.large)
                TextField("", text: $practice.progressionText, prompt: Text("Dm7 G7 Cmaj7").foregroundColor(unselectedColor))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 2).stroke(unselectedColor))
                    .frame(maxWidth: 520)

                keyMenu

                if !practice.unreadable.isEmpty {
                    Label("Not chords: \(practice.unreadable.joined(separator: " "))", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Button(action: practice.previousChord) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .help("Previous chord (⇧⌘[)")

                ForEach(Array(practice.chords.enumerated()), id: \.offset) { index, chord in
                    Text(chord.description)
                        .font(.system(size: 15, weight: index == practice.index ? .bold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(index == practice.index ? Color.white.opacity(0.2) : Color.clear))
                        .contentShape(Rectangle())
                        .gesture(TapGesture(count: 2).onEnded {
                            practice.select(chordAt: index)
                            replacing = index
                        }.exclusively(before: TapGesture().onEnded { practice.select(chordAt: index) }))
                        .popover(isPresented: Binding(get: { replacing == index }, set: { if !$0 { replacing = nil } }),
                                 arrowEdge: .bottom) {
                            ChordPalette(key: practice.key) { symbol in
                                practice.replaceChord(at: index, with: symbol)
                                replacing = nil
                            }
                        }
                        .contextMenu {
                            Button("Change…") { replacing = index }
                            Button("Move Left") { practice.moveChord(at: index, by: -1) }
                                .disabled(index == 0)
                            Button("Move Right") { practice.moveChord(at: index, by: 1) }
                                .disabled(index == practice.chords.count - 1)
                            Divider()
                            Button("Remove", role: .destructive) { practice.removeChord(at: index) }
                        }
                        .help("Click to practise, double-click to change, right-click for more")
                }
                
                Button {
                    addingChord = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("Add a chord")
                .popover(isPresented: $addingChord, arrowEdge: .bottom) {
                    // Stays open so several chords can be added in a row
                    ChordPalette(key: practice.key) { symbol in practice.appendChord(symbol) }
                }

                Button(action: practice.nextChord) { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .help("Next chord (⇧⌘])")
            }
        }
        .padding(12)
        .background(Color(hue: 0.63, saturation: 0.30, brightness: 0.20, opacity: 1.00))
    }

    private var keyMenu: some View {
        Menu {
            Button("Work it out\(practice.estimatedKey.map { " (\($0))" } ?? "")") { practice.keyOverride = nil }
            Divider()
            ForEach([KeyQuality.major, .minor], id: \.self) { quality in
                Menu(quality == .major ? "Major keys" : "Minor keys") {
                    ForEach(0..<12, id: \.self) { tonic in
                        let key = Key(conventional: PitchClass(tonic), quality)
                        Button(key.description) { practice.keyOverride = key }
                    }
                }
            }
        } label: {
            Text("Key: \(practice.key?.description ?? "none")\(practice.keyOverride == nil ? " (auto)" : "")")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Lists

private struct ScaleSuggestionList: View {
    @Environment(PracticeState.self) private var practice

    var body: some View {
        // The progression can become empty while typing; this list may redraw before its parent hides it
        if let chord = practice.current {
            list(for: chord)
        }
    }

    private func list(for chord: ChordSymbol) -> some View {
        let chosen = practice.scale?.id

        return VStack(alignment: .leading, spacing: 0) {
            Text("Scales over \(chord.description)")
                .font(.headline)
                .padding(12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(practice.scaleSuggestions) { suggestion in
                        let isSelected = suggestion.id == chosen && practice.focus == .scale

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(chord.root.description) \(suggestion.scale.name)")
                                .fontWeight(isSelected ? .semibold : .regular)
                            Text(suggestion.reasons.joined(separator: " · "))
                                .font(.caption)
                                .opacity(0.6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.white.opacity(0.15) : (suggestion.id == chosen ? Color.white.opacity(0.06) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { practice.choose(suggestion.scale) }
                    }
                }
            }
        }
    }
}

private struct ArpeggioList: View {
    @Environment(PracticeState.self) private var practice

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Arpeggios")
                .font(.headline)
                .padding(12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(practice.arpeggios) { arpeggio in
                        let isSelected = practice.focus == .arpeggio(arpeggio.id)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(practice.name(of: arpeggio))
                                .fontWeight(isSelected ? .semibold : .regular)
                            Text("\(kindName(arpeggio.kind)) · \(arpeggio.degreesOverChord.map(\.prettyDescription).joined(separator: " "))")
                                .font(.caption)
                                .opacity(0.6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.white.opacity(0.15) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            practice.focus = isSelected ? .scale : .arpeggio(arpeggio.id)
                        }
                    }
                }
            }
        }
    }

    private func kindName(_ kind: ArpeggioSuggestion.Kind) -> String {
        switch kind {
        case .chord: return "Chord tones"
        case .guideTones: return "Guide tones"
        case .upperStructure: return "Upper structure"
        }
    }
}

// MARK: - Detail

private struct PracticeDetail: View {
    @Environment(PracticeState.self) private var practice
    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var practice = practice

        VStack(spacing: 16) {
            if let voicing = practice.currentVoicing, let index = practice.currentVoicingIndex {
                HStack(spacing: 12) {
                    Button(action: practice.previousVoicing) { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                        .help("Previous voicing (⌘[)")
                    VStack(spacing: 2) {
                        Text(voicing.name)
                        Text("\(index + 1) of \(practice.voicings.count)")
                            .font(.caption)
                            .opacity(0.6)
                    }
                    .frame(minWidth: 280)
                    Button(action: practice.nextVoicing) { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                        .help("Next voicing (⌘])")
                }
            } else {
                Text("No playable voicing for this chord")
                    .opacity(0.6)
            }

            HStack(spacing: 16) {
                Picker("Voicings", selection: Binding(get: { practice.voicingSystem ?? "" },
                                                      set: { practice.voicingSystem = $0.isEmpty ? nil : $0 })) {
                    Text("All voicings").tag("")
                    ForEach(practice.voicingSystems, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 220)

                Toggle("Whole neck", isOn: $practice.wholeNeck)

                Picker("Colour", selection: $practice.colourByRole) {
                    Text("By role").tag(true)
                    Text("By interval").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            if let focus = practice.focusPlacement {
                Text(focus.name)
                    .font(.callout)
                    .opacity(0.8)
            }

            ToneMap()

            HStack(spacing: 12) {
                Button {
                    playback.preview(practice.chordEvents(clock: transport.clock))
                } label: {
                    Label("Chord", systemImage: "play.circle")
                }
                .help("Hear the voicing (⌘↩)")

                Button {
                    playback.preview(practice.focusEvents(clock: transport.clock))
                } label: {
                    Label(practice.focus == .scale ? "Scale" : "Arpeggio", systemImage: "play.circle")
                }
                .disabled(practice.focusPlacement == nil)
                .help("Hear the scale or arpeggio shown around the voicing")
            }
        }
        .padding(16)
    }
}

/// The 12 notes from the chord root, coloured by what they do over the chord.
private struct ToneMap: View {
    @Environment(PracticeState.self) private var practice
    @Environment(\.theme) private var theme

    var body: some View {
        if let chord = practice.current {
            let roles = practice.roles
            let chordDegrees = Dictionary(chord.chord.formula.degrees.map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })
            let scaleDegrees = Dictionary((practice.scale?.formula.degrees ?? []).map { ($0.pitchClassOffset, $0) }, uniquingKeysWith: { first, _ in first })

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<12, id: \.self) { offset in
                        let role = roles[offset] ?? .outside
                        let degree = chordDegrees[offset] ?? scaleDegrees[offset].map(ChordScaleMatcher.tensionName)
                        let note = degree.map { chord.root.spelling($0) }
                            ?? (practice.key ?? Key(conventional: chord.root.pitchClass, .major)).spell(chord.root.pitchClass.transposed(by: offset))

                        VStack(spacing: 2) {
                            Text(degree?.prettyDescription ?? "·")
                                .font(.system(size: 13, weight: .semibold))
                            Text(note.description)
                                .font(.caption)
                        }
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 4).fill(colour(role).opacity(role == .outside ? 0.15 : 0.85)))
                        .foregroundColor(role == .outside ? .white.opacity(0.5) : .black)
                    }
                }
                HStack(spacing: 14) {
                    legend("Chord tone", .chordTone)
                    legend("Tension", .tension)
                    legend("Avoid", .avoid)
                }
                .font(.caption)
            }
        }
    }

    private func legend(_ text: String, _ role: NoteRole) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour(role)).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func colour(_ role: NoteRole) -> Color {
        switch role {
        case .chordTone: return theme.chordToneColor
        case .tension: return theme.tensionColor
        case .avoid: return theme.avoidColor
        case .outside: return .white
        }
    }
}
