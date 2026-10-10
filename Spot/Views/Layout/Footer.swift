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
    @Environment(UIState.self) private var ui
    @State private var previousBPMChangeValue: CGFloat = 0

    let dimmed = Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00)

    private var editsSequence: Bool {
        ui.tab == .Sequence && session.isOpen
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
        Int((editsSequence ? session.playingTempo ?? transport.bpm : transport.bpm).rounded())
    }

    func incrementBPM(_ value: Int) {
        if editsSequence {
            session.setPlayingTempo(Double(bpm + value))
        } else {
            transport.incrementBPM(value)
        }
    }

    private func tap() {
        if editsSequence {
            session.tapTempo()
        } else if let tapped = session.tap() {
            transport.setBPM(tapped.rounded())
        }
    }

    // MARK: Time signature

    private var beatsPerBar: Int {
        editsSequence ? session.sequence?.beatsPerBar ?? 4 : transport.beatsPerBar
    }

    private func setBeatsPerBar(_ value: Int) {
        if editsSequence, let editor = session.editor, var sequence = session.sequence {
            sequence.beatsPerBar = value
            session.sequence = sequence
            editor.snap = Double(value)
            editor.select(beat: 0, extend: false, in: sequence)
        } else {
            transport.beatsPerBar = value
        }
    }

    /// Chords are on beats, so the time signature can't change under them.
    private var timeSignatureLocked: Bool {
        editsSequence && !(session.sequence?.chords.isEmpty ?? true)
    }

    var body: some View {
        HStack {
            Spacer()
            ModeSwitcher()
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

                Button(action: tap) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(editsSequence && session.sequence?.audio != nil
                      ? "Tap along with the recording to set its tempo (after four taps)"
                      : "Tap along with the beat to set the tempo (after four taps)")

                Menu {
                    ForEach([2, 3, 4, 5, 6, 7], id: \.self) { value in
                        Button("\(value)/4") { setBeatsPerBar(value) }
                    }
                } label: {
                    Text("\(beatsPerBar)/4")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(timeSignatureLocked)
                .help(timeSignatureLocked ? "Clear the chords to change the time signature" : "Time signature")
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

    private var tempoLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                Text("\(bpm)")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                // With a recording, a tempo other than its own is a practice speed: click to go back
                if editsSequence, let sequence = session.sequence, sequence.audio != nil,
                   abs(sequence.practiceRate - 1) > 0.001 {
                    Button("\(Int((sequence.practiceRate * 100).rounded()))% of \(Int(sequence.tempo.rounded()))") {
                        session.setPlayingTempo(sequence.tempo)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .help("Playing the recording slower or faster than it was played. Click for its own tempo.")
                }
            }
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
              ? "The tempo to play at. The recording slows down or speeds up to match, without changing pitch."
              : "Tempo")
    }
}
