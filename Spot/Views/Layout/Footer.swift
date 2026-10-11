//
//  Footer.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI
import SpotCore

/// Mode, transport, then the musical settings. On the Sequence tab (with a sequence open) the root,
/// tempo, tap and time signature belong to the sequence; elsewhere to the library selection and the metronome.
struct Footer: View {
    @Environment(SelectionState.self) private var selection
    @Environment(TransportState.self) private var transport
    @Environment(SequenceSession.self) private var session
    @Environment(TabSession.self) private var tabSession
    @Environment(UIState.self) private var ui
    @State private var previousBPMChangeValue: CGFloat = 0
    @State private var isTypingTimeSignature = false
    @State private var otherTimeSignature = ""

    let dimmed = Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00)

    /// The sequence's settings: on the Sequence tab, or on the Tab tab with the tab it links (they share them).
    private var editsSequence: Bool {
        session.isOpen && (ui.tab == .Sequence || (ui.tab == .Tab && tabSession.linkedSequence != nil))
    }

    /// On the Tab tab with a tab open, tempo and time signature are the tab's (at the cursor's bar).
    private var editsTab: Bool {
        ui.tab == .Tab && tabSession.isOpen && tabSession.linkedSequence == nil
    }

    // MARK: Root / key

    /// The sequence's key: the one chosen, or the one worked out from the chords.
    private var sequenceKey: Key? {
        session.sequence?.key ?? session.editor?.analysis.key
    }

    private func incrementRoot(_ value: Int) {
        if editsSequence {
            let key = sequenceKey ?? Key(conventional: PitchClass(0), .major)
            session.sequence?.key = Key(conventional: key.tonic.pitchClass.transposed(by: value), key.quality)
        } else {
            selection.transposeRoot(by: value)
        }
    }

    // MARK: Tempo

    private var bpm: Int {
        if editsTab, let tempo = tabSession.tempoAtCursor {
            return Int(tempo.rounded())
        }
        return Int((editsSequence ? session.sequence?.tempo ?? transport.bpm : transport.bpm).rounded())
    }

    func incrementBPM(_ value: Int) {
        if editsTab, let tempo = tabSession.tempoAtCursor {
            tabSession.tempoAtCursor = tempo.rounded() + Double(value)
        } else if editsSequence, let tempo = session.sequence?.tempo {
            session.sequence?.tempo = min(max(tempo.rounded() + Double(value), 20), 300)
            if !session.isPlaying, let tempo = session.sequence?.tempo {
                transport.setBPM(tempo)
            }
        } else {
            transport.incrementBPM(value)
        }
    }

    private func tap() {
        if editsTab {
            if let tapped = session.tap() {
                tabSession.tempoAtCursor = tapped.rounded()
            }
        } else if editsSequence {
            session.tapTempo()
        } else if let tapped = session.tap() {
            transport.setBPM(tapped.rounded())
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
        .background(.black)
        .foregroundColor(.white)
    }

    @ViewBuilder
    private var rootLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "tuningfork")
                .font(.system(size: 16))
                .foregroundColor(.white)

            if editsSequence {
                // Click for major / minor, or to go back to working the key out
                Menu {
                    let tonic = sequenceKey?.tonic.pitchClass ?? PitchClass(0)
                    Button("Major") { session.sequence?.key = Key(conventional: tonic, .major) }
                    Button("Minor") { session.sequence?.key = Key(conventional: tonic, .minor) }
                    Divider()
                    Button("Work It Out from the Chords") { session.sequence?.key = nil }
                } label: {
                    Text(sequenceKey.map { "\($0.tonic.description)\($0.quality == .minor ? "m" : "")" } ?? "–")
                        .font(.system(size: 20))
                        .foregroundColor(session.sequence?.key == nil ? dimmed : .white)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(minWidth: 50)
                .help("The sequence's key\(session.sequence?.key == nil ? " (worked out from the chords; change it to choose one)" : "")")
            } else {
                Text(selection.spelledRoot.description)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(minWidth: 50)
            }
        }
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
                .foregroundStyle(typed == nil ? Color.orange : .secondary)
        }
        .padding(14)
        .frame(width: 280)
    }

    private static func noteName(_ denominator: Int) -> String {
        [1: "whole note", 2: "half note", 4: "quarter note", 8: "eighth note", 16: "sixteenth note",
         32: "32nd note", 64: "64th note"][denominator] ?? "1/\(denominator)"
    }

    private var tempoLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .foregroundColor(.white)

            Text("\(bpm)")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(minWidth: 50)
        }
        .contentShape(Rectangle())
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
        .help(editsSequence && session.sequence?.audio != nil
              ? "The tempo to play at. The recording is sped up or slowed down from its own tempo to match, without changing pitch."
              : "Tempo")
    }
}
