//
//  TabTabView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// The Tab tab: the open tab (tablature) file, or a way to start or open one.
struct TabTabView: View {
    @Environment(TabSession.self) private var session
    @Environment(SequenceSession.self) private var sequenceSession
    @Environment(UIState.self) private var ui

    var body: some View {
        if session.isSequenceTab, sequenceSession.isPreparingAudio {
            // The sequence's tab plays with its recording: wait for it, as the Sequence tab does
            AudioLoadingView(fileName: sequenceSession.sequence?.audio?.reference.fileName)
        } else if session.isOpen {
            TabEditorView()
        } else {
            launcher
        }
    }

    private var launcher: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Tab")
                    .font(.largeTitle)
                Text("Write and read tablature. Each tab is saved as a .spottab file. Open… also opens Guitar Pro files (versions 3 to 8), and File ▸ Export as Guitar Pro… writes one.")
                    .multilineTextAlignment(.center)
                    .opacity(0.7)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 16) {
                Button {
                    ui.requestTabAction(.new, session: session)
                } label: {
                    Label("New Tab", systemImage: "plus")
                        .frame(minWidth: 160)
                }
                Button {
                    ui.requestTabAction(.open, session: session)
                } label: {
                    Label("Open…", systemImage: "folder")
                        .frame(minWidth: 160)
                }
            }
            .controlSize(.large)

            if !session.recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                    ForEach(session.recents) { recent in
                        HStack {
                            Button {
                                ui.requestTabAction(.openRecent(recent), session: session)
                            } label: {
                                Label(recent.name, systemImage: "music.quarternote.3")
                            }
                            .buttonStyle(.link)
                            Spacer()
                            Button {
                                session.removeRecent(recent)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .opacity(0.5)
                            .help("Remove from the list")
                        }
                    }
                }
                .frame(width: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The open tab: a bar with which file and track, the tablature (type into it once it's clicked), and a
/// toolbar for note values, rests, ties, bars and beats.
private struct TabEditorView: View {
    @Environment(TabSession.self) private var session
    @State private var showsDetails = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if let score = session.score, let editor = session.editor {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "music.quarternote.3")
                            .opacity(0.6)
                        Text(session.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        if session.needsSaveBeforeClosing {
                            Text("Not saved")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        } else if let error = session.saveError {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help(error)
                        }
                    }

                    // The sequence's tab: one transport with it
                    if session.linkedSequence != nil {
                        Label("Sequence tab", systemImage: "music.note.list")
                            .font(.callout)
                            .foregroundStyle(.cyan)
                            .help("The open sequence's tab, saved with it. They play together: Space, ⌥Space (from the cursor), the loop (⌘L loops the selected beats), the start marker, end and playhead are shared, and so are tempo and time signature in the footer. Open… brings a .spottab or Guitar Pro file into it (⌘Z to undo).")
                    }

                    if score.tracks.count > 1 {
                        Picker("Track", selection: Binding(get: { editor.track }, set: { editor.track = $0; editor.clamp(to: score) })) {
                            ForEach(Array(score.tracks.enumerated()), id: \.element.id) { index, track in
                                Text(track.name.isEmpty ? "Track \(index + 1)" : track.name).tag(index)
                            }
                        }
                        .fixedSize()
                    } else if let track = score.tracks.first {
                        Text(track.name)
                            .opacity(0.7)
                    }

                    Spacer()

                    Button {
                        showsDetails.toggle()
                    } label: {
                        Label("Details", systemImage: "slider.horizontal.3")
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderless)
                    .help("Title, artist, tempo, bars and tracks")
                    .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                        TabDetails()
                            .frame(width: 760)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                TabStaffView(score: score, editor: editor)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($isFocused)
                    .simultaneousGesture(TapGesture().onEnded { isFocused = true })
                    .onKeyPress(phases: .down) { press in handle(press) ? .handled : .ignored }
                    .onAppear {
                        isFocused = true
                        session.followSequence()
                    }
                    .onDisappear { session.stopFollowingSequence() }
                    .onChange(of: editor.cursor) { session.cursorMoved() }

                Divider()

                TabToolbar(score: score, editor: editor)
            }
        }
    }

    /// The editor's keys (see `TabKeysHelp`).
    private func handle(_ press: KeyPress) -> Bool {
        let shift = press.modifiers.contains(.shift)
        if press.modifiers.contains(.command) {
            switch press.characters.lowercased() {
            case "c": session.copySelection()
            case "x": session.cutSelection()
            case "v": session.paste()
            default: return false
            }
            return true
        }
        switch press.key {
        case .leftArrow: session.moveBeat(by: -1, extending: shift)
        case .rightArrow: session.moveBeat(by: 1, extending: shift)
        case .upArrow: session.moveString(by: 1)
        case .downArrow: session.moveString(by: -1)
        case .delete, .deleteForward: session.deleteAtCursor()
        default:
            // With ⇧: let ring, and slides in or out
            switch press.characters {
            case "L": session.toggle(.letRing); return true
            case "S": session.cycleSlideInOut(); return true
            default: break
            }
            let character = press.characters.lowercased()
            if let digit = Int(character), character.count == 1 {
                session.typeDigit(digit)
            } else {
                switch character {
                case "-": session.changeDuration(by: -1)
                case "=", "+": session.changeDuration(by: 1)
                case ".": session.toggleDot()
                case "/": session.toggleTriplet()
                case "r": session.makeRest()
                case "l": session.toggleTie()
                case "i": session.insertBeat()
                case "h": session.toggle(.legato)
                case "s": session.toggle(.slide)
                case "b": session.cycleBend()
                case "v": session.toggle(.vibrato)
                case "m": session.toggle(.palmMute)
                case "x": session.toggle(.dead)
                case "g": session.toggle(.ghost)
                case "n": session.toggle(.harmonic)
                case "t": session.toggle(.tapped)
                case "a": session.toggle(.accent)
                default: return false
                }
            }
        }
        return true
    }
}

/// Under the tab: the note value (and dot, triplet), rest, tie, insert and delete, the bar's and beat's
/// settings, the keys, and where the cursor is.
private struct TabToolbar: View {
    let score: TabScore
    let editor: TabEditorState

    @Environment(TabSession.self) private var session
    @State private var showsBar = false
    @State private var showsBeat = false
    @State private var showsKeys = false

    private static let names: [(TabDuration.Value, String)] = [
        (.whole, "Whole"), (.half, "Half"), (.quarter, "Quarter"), (.eighth, "8th"),
        (.sixteenth, "16th"), (.thirtySecond, "32nd"), (.sixtyFourth, "64th"),
    ]

    var body: some View {
        let duration = editor.beat(in: score)?.duration ?? editor.duration
        HStack(spacing: 12) {
            BarMenu(title: "Note", value: (Self.names.first { $0.0 == duration.value }?.1 ?? "") + (duration.dots > 0 ? " dotted" : "")
                        + (duration.tuplet != nil ? " triplet" : ""),
                    help: "The note value: of the beat at the cursor, and of new beats (− shorter, = longer, . dot, / triplet)") {
                ForEach(Self.names, id: \.0) { value, name in
                    Toggle(name, isOn: Binding(get: { duration.value == value }, set: { _ in session.setDuration(value) }))
                }
            }
            toolButton("Dot", systemImage: "circle.fill", isOn: duration.dots > 0, help: "Dotted (.)") { session.toggleDot() }
            toolButton("Triplet", systemImage: "3.circle", isOn: duration.tuplet != nil, help: "Triplet (/)") { session.toggleTriplet() }

            Divider().frame(height: 18)

            toolButton("Rest", systemImage: "pause", help: "Make the beat a rest (R)") { session.makeRest() }
            toolButton("Tie", systemImage: "link", isOn: editor.beat(in: score)?.notes.first { $0.string == editor.cursor.string }?.isTied == true,
                       help: "Tie to the note before on this string (L)") { session.toggleTie() }
            toolButton("Insert", systemImage: "plus.square", help: "Insert a beat before the cursor (I)") { session.insertBeat() }
            toolButton("Delete", systemImage: "delete.left", help: "Delete the note, or the beat if it's a rest (⌫)") { session.deleteAtCursor() }

            Divider().frame(height: 18)

            techniqueMenu

            Divider().frame(height: 18)

            Button {
                showsBar.toggle()
            } label: {
                Label("Bar \(editor.cursor.bar + 1)", systemImage: "rectangle.split.3x1")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
            .help("Time signature, repeats, endings, marker and tempo of this bar")
            .popover(isPresented: $showsBar, arrowEdge: .top) { BarSettings(bar: editor.cursor.bar) }

            Button {
                showsBeat.toggle()
            } label: {
                Label("Beat", systemImage: "textformat")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
            .disabled(editor.beat(in: score) == nil)
            .help("Chord name and text above this beat")
            .popover(isPresented: $showsBeat, arrowEdge: .top) { BeatSettings() }

            Spacer()

            status
                .font(.callout)

            Button {
                showsKeys.toggle()
            } label: {
                Image(systemName: "keyboard")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
            .help("Keys")
            .popover(isPresented: $showsKeys, arrowEdge: .top) { TabKeysHelp() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Techniques for the note at the cursor (or every note in the selected beats), ticked when they all have it.
    private var techniqueMenu: some View {
        let toggles: [(TabSession.Technique, String, String)] = [
            (.legato, "Hammer-on / Pull-off", "H"), (.slide, "Slide to Next Note", "S"), (.vibrato, "Vibrato", "V"),
            (.palmMute, "Palm Mute", "M"), (.letRing, "Let Ring", "⇧L"), (.dead, "Dead Note", "X"), (.ghost, "Ghost Note", "G"),
            (.harmonic, "Natural Harmonic", "N"), (.tapped, "Tapping", "T"), (.accent, "Accent", "A"),
        ]
        return BarMenu(title: "Technique", value: "", help: "Techniques for the note at the cursor, or every note in the selected beats") {
            ForEach(toggles, id: \.1) { technique, name, key in
                Toggle("\(name)  (\(key))", isOn: Binding(get: { session.isOn(technique) }, set: { _ in session.toggle(technique) }))
            }
            Divider()
            Menu("Bend (B)") {
                Button("Full") { session.setBend(.up(200)) }
                Button("½") { session.setBend(.up(100)) }
                Button("¼") { session.setBend(.up(50)) }
                Button("1½") { session.setBend(.up(300)) }
                Button("Full and Release") { session.setBend(.upAndRelease(200)) }
                Button("½ and Release") { session.setBend(.upAndRelease(100)) }
                Button("Pre-bend Full and Release") { session.setBend(.prebendRelease(200)) }
                Divider()
                Button("No Bend") { session.setBend(nil) }
            }
            Menu("Slide") {
                Button("To Next Note (S)") { session.setSlide(.shift) }
                Button("Legato to Next Note") { session.setSlide(.legato) }
                Button("In from Below") { session.setSlide(.inFromBelow) }
                Button("In from Above") { session.setSlide(.inFromAbove) }
                Button("Out Downwards") { session.setSlide(.outDownwards) }
                Button("Out Upwards") { session.setSlide(.outUpwards) }
                Divider()
                Button("No Slide") { session.setSlide(nil) }
            }
            Menu("Harmonic") {
                Button("Natural (N)") { session.setHarmonic(.natural) }
                Button("Artificial") { session.setHarmonic(.artificial) }
                Button("Pinch") { session.setHarmonic(.pinch) }
                Button("Tapped") { session.setHarmonic(.tapped) }
                Button("Semi") { session.setHarmonic(.semi) }
                Divider()
                Button("No Harmonic") { session.setHarmonic(nil) }
            }
        }
    }

    /// Where the cursor is, and whether the bar adds up.
    @ViewBuilder
    private var status: some View {
        let track = score.tracks.indices.contains(editor.track) ? score.tracks[editor.track] : nil
        let fill = score.fill(track: editor.track, bar: editor.cursor.bar)
        HStack(spacing: 10) {
            if fill != 0 {
                Label(fill < 0 ? "Bar \(editor.cursor.bar + 1) is short by \(describe(-fill))" : "Bar \(editor.cursor.bar + 1) is over by \(describe(fill))",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(fill < 0 ? .orange : .red)
            }
            if let track, track.tuning.strings.indices.contains(editor.cursor.string) {
                let open = SpelledNote.conventional(PitchClass(track.tuning.strings[editor.cursor.string] + track.capo))
                Text("Bar \(editor.cursor.bar + 1) · beat \(editor.cursor.beat + 1) · string \(track.stringCount - editor.cursor.string) (\(open.description))")
                    .monospacedDigit()
                    .opacity(0.7)
            }
        }
    }

    /// e.g. "a quarter", "an 8th", "3 16ths".
    private func describe(_ ticks: Int) -> String {
        for (value, name) in Self.names.reversed().reversed() {
            let size = TabDuration(value).ticks
            if ticks % size == 0 {
                let count = ticks / size
                return count == 1 ? (name == "8th" ? "an 8th" : "a \(name.lowercased())") : "\(count) \(name.lowercased())s"
            }
        }
        return "\(ticks) ticks"
    }

    private func toolButton(_ title: String, systemImage: String, isOn: Bool = false, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isOn ? Color.accentColor : .white)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// The bar at the cursor: time signature (from here until the next change), repeats, endings, marker, tempo.
private struct BarSettings: View {
    let bar: Int

    @Environment(TabSession.self) private var session

    var body: some View {
        if let score = session.score, score.masterBars.indices.contains(bar) {
            let master = score.masterBars[bar]
            let binding = Binding(get: { session.score?.masterBars[bar] ?? master }, set: { session.score?.masterBars[bar] = $0 })
            Form {
                LabeledContent("Time signature") {
                    HStack {
                        Picker("", selection: Binding(get: { master.timeSignature.numerator }, set: {
                            session.score?.setTimeSignature(TimeSignature($0, master.timeSignature.denominator), from: bar)
                        })) {
                            ForEach(1...32, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 60)
                        Text("/")
                        Picker("", selection: Binding(get: { master.timeSignature.denominator }, set: {
                            session.score?.setTimeSignature(TimeSignature(master.timeSignature.numerator, $0), from: bar)
                        })) {
                            ForEach([1, 2, 4, 8, 16, 32, 64], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 60)
                    }
                }
                Toggle("Repeat starts here", isOn: binding.isRepeatStart)
                Stepper(value: binding.repeatCount, in: 0...16) {
                    Text(master.repeatCount == 0 ? "No repeat ends here" : "Repeat ends here, played \(master.repeatCount) times")
                }
                TextField("Endings", text: Binding(get: { master.alternateEndings.map(String.init).joined(separator: ", ") }, set: { text in
                    session.score?.masterBars[bar].alternateEndings = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                }), prompt: Text("e.g. 1 or 1, 2"))
                TextField("Marker", text: Binding(get: { master.marker ?? "" }, set: {
                    session.score?.masterBars[bar].marker = $0.isEmpty ? nil : $0
                }), prompt: Text("e.g. Verse"))
                Toggle("Tempo change", isOn: Binding(get: { master.tempo != nil }, set: {
                    session.score?.masterBars[bar].tempo = $0 ? score.tempo : nil
                }))
                if let tempo = master.tempo {
                    Stepper(value: Binding(get: { tempo }, set: { session.score?.masterBars[bar].tempo = $0 }), in: 20...400) {
                        Text("♩ = \(Footer.tempoText(tempo))")
                            .monospacedDigit()
                    }
                }
                HStack {
                    Button("Insert Bar After") { session.score?.insertBar(after: bar) }
                    Button("Delete Bar", role: .destructive) { session.score?.removeBar(at: bar) }
                        .disabled(score.barCount <= 1)
                }
            }
            .formStyle(.grouped)
            .frame(width: 380)
        }
    }
}

/// The beat at the cursor: a chord name and text above it, and a strum direction.
private struct BeatSettings: View {
    @Environment(TabSession.self) private var session

    var body: some View {
        if let editor = session.editor, let score = session.score, let beat = editor.beat(in: score) {
            Form {
                TextField("Chord", text: Binding(get: { beat.chord ?? "" }, set: { text in
                    session.score?.updateBeat(track: editor.track, at: editor.position) { $0.chord = text.isEmpty ? nil : text }
                }), prompt: Text("e.g. Am7"))
                TextField("Text", text: Binding(get: { beat.text ?? "" }, set: { text in
                    session.score?.updateBeat(track: editor.track, at: editor.position) { $0.text = text.isEmpty ? nil : text }
                }))
                Picker("Strum", selection: Binding(get: { beat.stroke }, set: { stroke in
                    session.score?.updateBeat(track: editor.track, at: editor.position) { $0.stroke = stroke }
                })) {
                    Text("None").tag(TabBeat.Stroke?.none)
                    Text("Down").tag(TabBeat.Stroke?.some(.down))
                    Text("Up").tag(TabBeat.Stroke?.some(.up))
                }
            }
            .formStyle(.grouped)
            .frame(width: 320)
        }
    }
}

/// The editor's keys.
private struct TabKeysHelp: View {
    private let keys: [(String, String)] = [
        ("0–9", "Fret on the cursor's string (two digits quickly for 10–29)"),
        ("← →", "Previous / next beat (past a full bar into the next)"),
        ("↑ ↓", "Higher / lower string"),
        ("⇧← ⇧→", "Select beats"),
        ("− =", "Shorter / longer note value"),
        (".", "Dotted"),
        ("/", "Triplet"),
        ("R", "Rest"),
        ("L", "Tie to the previous note"),
        ("I", "Insert a beat"),
        ("⌫", "Delete the note (on a rest, the beat)"),
        ("H", "Hammer-on / pull-off to the next note"),
        ("S  ⇧S", "Slide to the next note; slide in or out"),
        ("B", "Bend: full, ½, full and release, pre-bend, none"),
        ("V", "Vibrato"),
        ("M  ⇧L", "Palm mute; let ring"),
        ("X  G", "Dead note; ghost note"),
        ("N", "Natural harmonic"),
        ("T  A", "Tapping; accent"),
        ("⌘C ⌘X ⌘V", "Copy, cut, paste beats"),
        ("⌘Z ⇧⌘Z", "Undo, redo"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(keys, id: \.0) { key, meaning in
                GridRow {
                    Text(key)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Text(meaning)
                        .font(.callout)
                }
            }
        }
        .padding(16)
    }
}

/// Title, artist, tempo, bars and tracks.
private struct TabDetails: View {
    @Environment(TabSession.self) private var session

    var body: some View {
        if let score = session.score {
            let binding = Binding(get: { session.score ?? score }, set: { session.score = $0 })
            VStack(alignment: .leading, spacing: 14) {
                Form {
                    TextField("Title", text: binding.title)
                    TextField("Artist", text: binding.artist)
                    Stepper(value: binding.tempo, in: 20...400, step: 1) {
                        Text("Tempo \(Footer.tempoText(score.tempo))")
                            .monospacedDigit()
                    }
                    Stepper {
                        Text("\(score.barCount) bars")
                            .monospacedDigit()
                    } onIncrement: {
                        session.score?.insertBar()
                    } onDecrement: {
                        session.score?.removeBar(at: score.barCount - 1)
                    }
                }
                .formStyle(.grouped)

                Text("Tracks")
                    .font(.headline)
                ForEach(Array(score.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: binding.tracks[index], canRemove: score.tracks.count > 1) {
                        session.score?.tracks.remove(at: index)
                    }
                }
                Button {
                    session.score?.tracks.append(TabTrack(name: "Guitar \(score.tracks.count + 1)", barCount: score.barCount))
                } label: {
                    Label("Add Track", systemImage: "plus")
                }
            }
            .padding(20)
        }
    }
}

private struct TrackRow: View {
    @Binding var track: TabTrack
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            TextField("Name", text: $track.name)
                .frame(width: 160)
            Picker("Tuning", selection: Binding(get: { track.tuning.id }, set: { id in
                if let tuning = Tuning.presets.first(where: { $0.id == id }) {
                    track.tuning = tuning
                }
            })) {
                ForEach(Tuning.presets) { tuning in
                    Text(tuning.name).tag(tuning.id)
                }
                if !Tuning.presets.contains(where: { $0.id == track.tuning.id }) {
                    Text(track.tuning.name).tag(track.tuning.id)
                }
            }
            .frame(width: 220)
            Stepper(value: $track.capo, in: 0...12) {
                Text(track.capo == 0 ? "No capo" : "Capo \(track.capo)")
                    .monospacedDigit()
            }
            .frame(width: 130)
            Picker("Sound", selection: $track.midiProgram) {
                Text("Nylon guitar").tag(24)
                Text("Steel guitar").tag(25)
                Text("Jazz guitar").tag(26)
                Text("Clean electric").tag(27)
                Text("Overdriven").tag(29)
                Text("Distortion").tag(30)
                Text("Bass (finger)").tag(33)
                Text("Bass (pick)").tag(34)
            }
            .frame(width: 200)
            if canRemove {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this track")
            }
        }
    }
}
