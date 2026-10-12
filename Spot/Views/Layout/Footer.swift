//
//  Footer.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI
import SpotCore

/// Mode, transport, then the musical settings. The key is always the sequence's (the Library has its own root, in
/// its panel, so picking a scale there never changes a sequence). On the Sequence tab (with a sequence open) the
/// tempo, tap and time signature belong to the sequence too; elsewhere to the metronome.
struct Footer: View {
    @Environment(SelectionState.self) private var selection
    @Environment(TransportState.self) private var transport
    @Environment(SequenceSession.self) private var session
    @Environment(TabSession.self) private var tabSession
    @Environment(UIState.self) private var ui
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(DisplaySettings.self) private var display
    @State private var previousBPMChangeValue: CGFloat = 0
    @State private var isPickingKey = false
    @State private var isPickingSpeed = false
    @State private var isTypingTimeSignature = false
    @State private var otherTimeSignature = ""
    @State private var isTypingTempo = false
    @State private var typedTempo = ""

    var dimmed: Color { SpotStyle.dimmed }

    /// The sequence's settings: on the Sequence tab, or on the Tab tab with the tab it links (they share them).
    private var editsSequence: Bool {
        session.isOpen && (ui.tab == .Sequence || (ui.tab == .Tab && tabSession.linkedSequence != nil))
    }

    /// On the Tab tab with a tab open, tempo and time signature are the tab's (at the cursor's bar).
    private var editsTab: Bool {
        ui.tab == .Tab && tabSession.isOpen && tabSession.linkedSequence == nil
    }

    // MARK: Key (the sequence's)

    /// The sequence's key: the one chosen, or the one worked out from the chords.
    private var sequenceKey: Key? {
        session.sequence?.key ?? session.editor?.analysis.key
    }

    private func incrementRoot(_ value: Int) {
        guard session.isOpen else { return }
        let key = sequenceKey ?? Key(conventional: PitchClass(0), .major)
        session.sequence?.key = Key(conventional: key.tonic.pitchClass.transposed(by: value), key.quality)
    }

    // MARK: Tempo

    private var bpm: Double {
        if editsTab, let tempo = tabSession.tempoAtCursor {
            return tempo
        }
        return editsSequence ? session.sequence?.tempo ?? transport.bpm : transport.bpm
    }

    /// The tempo as shown: whole, or to as many decimal places as it has (up to two).
    static func tempoText(_ bpm: Double) -> String {
        var text = String(format: "%.2f", (bpm * 100).rounded() / 100)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The arrows (and dragging the number): a whole bpm a step, or a tenth with ⌥ held.
    func incrementBPM(_ direction: Int) {
        let fine = NSEvent.modifierFlags.contains(.option)
        setBPM(bpm + Double(direction) * (fine ? 0.1 : 1))
    }

    /// Kept to two decimal places (a sequence's or tab's within 20–300).
    private func setBPM(_ value: Double) {
        let rounded = (value * 100).rounded() / 100
        let tempo = min(max(rounded, 20), 300)
        if editsTab, tabSession.tempoAtCursor != nil {
            tabSession.tempoAtCursor = tempo
        } else if editsSequence, session.sequence != nil {
            session.sequence?.tempo = tempo
            if !session.isPlaying {
                transport.setBPM(tempo)
            }
        } else {
            transport.setBPM(rounded)
        }
    }

    private func tap() {
        if editsTab {
            if let tapped = session.tap() {
                tabSession.tempoAtCursor = tapped
            }
        } else if editsSequence {
            session.tapTempo()
        } else if let tapped = session.tap() {
            transport.setBPM(tapped)
        }
    }

    // MARK: Time signature

    private var timeSignature: TimeSignature {
        if editsTab, let signature = tabSession.timeSignatureAtCursor {
            return signature
        }
        return editsSequence ? session.sequence?.timeSignature ?? TimeSignature(4, 4) : transport.timeSignature
    }

    /// Any time signature. Chords, sections, loops and warp markers are all in beats (quarter notes), so changing
    /// it just regroups them into bars (and can be undone).
    private func setTimeSignature(_ signature: TimeSignature) {
        guard signature.isValid, signature != timeSignature else { return }
        if editsTab {
            tabSession.setTimeSignature(signature)
        } else if editsSequence {
            // (A grid of bars stays bars: the grid is kept in bars or note values, not beats)
            session.sequence?.timeSignature = signature
        } else {
            transport.timeSignature = signature
        }
    }

    /// The arrows change the top number.
    private func stepTimeSignature(_ step: Int) {
        let current = timeSignature
        setTimeSignature(TimeSignature(min(max(current.numerator + step, 1), 32), current.denominator))
    }

    /// The menu's choices.
    private static let commonTimeSignatures: [[TimeSignature]] = [
        [TimeSignature(2, 4), TimeSignature(3, 4), TimeSignature(4, 4), TimeSignature(5, 4), TimeSignature(6, 4), TimeSignature(7, 4)],
        [TimeSignature(3, 8), TimeSignature(5, 8), TimeSignature(6, 8), TimeSignature(7, 8), TimeSignature(9, 8), TimeSignature(12, 8)],
        [TimeSignature(2, 2), TimeSignature(3, 2)],
    ]
    
    var body: some View {
        HStack {
            Spacer()
            ModeSwitcher()
            Spacer()
            Button {
                ui.isFretboardOnly.toggle()
            } label: {
                Image(systemName: ui.isFretboardOnly && ui.tab != .Settings ? "rectangle.split.1x2" : "rectangle.split.1x2.fill")
                    .font(.system(size: 17))
                    .foregroundColor(ui.tab == .Settings ? dimmed : .white)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ui.tab == .Settings)
            .help(ui.tab == .Tab
                  ? (ui.hidesFretboard ? "Show the fretboard (⇧⌘F)" : "Just the tab: hide the fretboard (⇧⌘F)")
                  : (ui.showsFretboardOnly ? "Show the panel below the fretboard (⇧⌘F)" : "Just the fretboard: hide the panel below it (⇧⌘F)"))
            // The notes on the guitar's neck or on a piano
            Button {
                display.instrument = display.instrument == .piano ? .guitar : .piano
            } label: {
                Image(systemName: display.instrument == .piano ? "guitars" : "pianokeys")
                    .font(.system(size: 17))
                    .foregroundColor(ui.tab == .Settings ? dimmed : .white)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(ui.tab == .Settings)
            .help(display.instrument == .piano ? "Show the fretboard (⌥⌘K)" : "Show the notes on a piano (⌥⌘K)")
            Spacer()
            Transport()
            Spacer()
            HStack(spacing: 14) {
                RangePicker(data: 0..<12,
                            onDecrement: { incrementRoot(-1) },
                            onIncrement: { incrementRoot(1) }) { _ in
                    rootLabel
                }

                RangePicker(data: 1..<10,
                            onDecrement: { incrementBPM(-1) },
                            onIncrement: { incrementBPM(1) }) { _ in
                    tempoLabel
                }

                practiceSpeedButton

                RangePicker(data: 1..<33,
                            onDecrement: { stepTimeSignature(-1) },
                            onIncrement: { stepTimeSignature(1) }) { _ in
                    timeSignatureLabel
                }

                Button(action: tap) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tap along with the beat to set the tempo (after four taps)")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(ThemeStore.shared.current.footer)
        .foregroundColor(.white)
    }

    @ViewBuilder
    private var rootLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "tuningfork")
                .font(.system(size: 16))
                .foregroundColor(.white)

            // Click to choose major, minor or a mode; ⇧-click to swap between major and minor
            Button {
                if NSEvent.modifierFlags.contains(.shift) {
                    swapMajorMinor()
                } else {
                    isPickingKey = true
                }
            } label: {
                Text(keyLabel)
                    .font(.system(size: 20))
                    .foregroundColor(session.sequence?.key == nil ? dimmed : .white)
                    .frame(minWidth: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.isOpen)
            .popover(isPresented: $isPickingKey, arrowEdge: .top) {
                keyPicker
            }
            .help(session.isOpen
                  ? "The sequence's key\(session.sequence?.key == nil ? " (worked out from the chords)" : ""). Click to choose major, minor or a mode; ⇧-click to swap major and minor. The arrows change the root."
                  : "The sequence's key, once one is open. (The Library's root is in its panel.)")
        }
    }

    /// The key as shown: "B", "Bm", "B dor".
    private var keyLabel: String {
        sequenceKey?.shortName ?? "–"
    }

    private var currentQuality: KeyQuality? {
        sequenceKey?.quality
    }

    private func setQuality(_ quality: KeyQuality) {
        guard session.isOpen else { return }
        let tonic = sequenceKey?.tonic.pitchClass ?? PitchClass(0)
        session.sequence?.key = Key(conventional: tonic, quality)
    }

    /// ⇧-click: major to minor (on the same root), and anything minor-sounding to major.
    private func swapMajorMinor() {
        setQuality(currentQuality?.isMinor == true ? .major : .minor)
    }

    /// Major or minor, the other modes, and working the key out from the chords.
    private var keyPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key")
                .font(.headline)
            HStack(spacing: 6) {
                keyChoice(.major, title: "Major")
                keyChoice(.minor, title: "Minor")
            }
            Text("Modes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach([KeyQuality.dorian, .phrygian, .lydian, .mixolydian, .locrian], id: \.self) { quality in
                    keyChoice(quality, title: quality.name)
                }
            }
            Divider()
            Toggle("Work it out from the chords", isOn: Binding(
                get: { session.sequence?.key == nil },
                set: { automatic in
                    if automatic {
                        session.sequence?.key = nil
                    } else if let key = sequenceKey {
                        session.sequence?.key = key
                    }
                }))
            Text("⇧-click the key to swap major and minor")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func keyChoice(_ quality: KeyQuality, title: String) -> some View {
        let isOn = currentQuality == quality && session.sequence?.key != nil
        return Button {
            setQuality(quality)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08)))
    }

    private var timeSignatureLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 14))
                .foregroundColor(.white)
            Menu {
                ForEach(Footer.commonTimeSignatures, id: \.self) { group in
                    ForEach(group, id: \.self) { signature in
                        Toggle(signature.description, isOn: Binding(get: { signature == timeSignature },
                                                                    set: { _ in setTimeSignature(signature) }))
                    }
                    Divider()
                }
                Button("Other…") {
                    otherTimeSignature = timeSignature.description
                    isTypingTimeSignature = true
                }
            } label: {
                Text(timeSignature.description)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(minWidth: 44)
            .popover(isPresented: $isTypingTimeSignature, arrowEdge: .top) {
                timeSignatureEditor
            }
        }
        .help("Time signature: choose one, or Other… to type any (7/8, 11/16…). The arrows change the beats in a bar.")
    }

    /// Typing a time signature.
    private var timeSignatureEditor: some View {
        let typed = TimeSignature(otherTimeSignature)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Time Signature")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("7/8", text: $otherTimeSignature)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                    .frame(width: 90)
                    .onSubmit {
                        if let typed {
                            setTimeSignature(typed)
                            isTypingTimeSignature = false
                        }
                    }
                Button("Set") {
                    if let typed {
                        setTimeSignature(typed)
                        isTypingTimeSignature = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(typed == nil)
            }
            Text(typed == nil ? "Beats (1–32) / note value (1, 2, 4, 8, 16, 32 or 64)" : "\(typed!.numerator) beats of a \(Footer.noteName(typed!.denominator)) to the bar")
                .font(.caption)
                .foregroundStyle(typed == nil ? SpotStyle.warning : .secondary)
        }
        .padding(14)
        .frame(width: 280)
    }

    private static func noteName(_ denominator: Int) -> String {
        [1: "whole note", 2: "half note", 4: "quarter note", 8: "eighth note", 16: "sixteenth note",
         32: "32nd note", 64: "64th note"][denominator] ?? "1/\(denominator)"
    }

    /// Practice speed: play slower (or faster) without changing the tempo. Lit up when it isn't 100%; click for the
    /// presets.
    private var practiceSpeedButton: some View {
        let speed = playback.practiceSpeed
        return Button {
            isPickingSpeed = true
        } label: {
            Text("\(Int((speed * 100).rounded()))%")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundColor(speed == 1 ? dimmed : .black)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(speed == 1 ? Color.clear : SpotStyle.warning))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPickingSpeed, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Practice Speed")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(PlaybackController.practiceSpeeds, id: \.self) { preset in
                        let isOn = abs(speed - preset) < 0.001
                        Button {
                            playback.setPracticeSpeed(preset)
                        } label: {
                            Text("\(Int((preset * 100).rounded()))%")
                                .font(.system(size: 13, weight: isOn ? .semibold : .regular).monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08)))
                    }
                }
                Text("Plays at a percentage of the tempo, without changing it (or the recording's pitch). ⌥⌘− and ⌥⌘= step it by 5%, ⌥⌘0 goes back to normal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260)
        }
        .help("Practice speed: play at a percentage of the tempo, leaving the tempo as it is (⌥⌘− / ⌥⌘= / ⌥⌘0)")
    }

    private var tempoLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .foregroundColor(.white)

            Text(Footer.tempoText(bpm))
                .font(.system(size: 20).monospacedDigit())
                .foregroundColor(.white)
                .frame(minWidth: 50)
        }
        .contentShape(Rectangle())
        // Double-click to type it (any tempo, decimals and all)
        .onTapGesture(count: 2) {
            typedTempo = Footer.tempoText(bpm)
            isTypingTempo = true
        }
        .popover(isPresented: $isTypingTempo, arrowEdge: .top) {
            tempoEditor
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width < previousBPMChangeValue {
                        incrementBPM(-1)
                    } else if value.translation.width > previousBPMChangeValue {
                        incrementBPM(1)
                    }
                    previousBPMChangeValue = value.translation.width
                }
                .onEnded { _ in previousBPMChangeValue = 0 })
        .help((editsSequence && session.sequence?.audio != nil
              ? "The tempo to play at. The recording is sped up or slowed down from its own tempo to match, without changing pitch."
              : "Tempo") + " Drag or use the arrows to change it (⌥ for tenths); double-click to type it.")
    }

    /// Typing a tempo.
    private var tempoEditor: some View {
        let typed = Double(typedTempo.trimmingCharacters(in: .whitespaces)).flatMap { (20...300).contains($0) ? $0 : nil }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tempo")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("120.5", text: $typedTempo)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                    .frame(width: 90)
                    .onSubmit {
                        if let typed {
                            setBPM(typed)
                            isTypingTempo = false
                        }
                    }
                Button("Set") {
                    if let typed {
                        setBPM(typed)
                        isTypingTempo = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(typed == nil)
            }
            Text(typed == nil ? "20 to 300, with decimals if you like (e.g. 92.5)" : "\(Footer.tempoText(typed!)) beats a minute")
                .font(.caption)
                .foregroundStyle(typed == nil ? SpotStyle.warning : .secondary)
        }
        .padding(14)
        .frame(width: 240)
    }
}
