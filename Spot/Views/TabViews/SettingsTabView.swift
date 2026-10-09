//
//  SettingsTabView.swift
//  Spot
//

import SwiftUI
import CoreMIDI
import SpotCore

struct SettingsTabView: View {
    @Environment(AudioSettings.self) private var settings
    @Environment(PlaybackController.self) private var playback

    @State private var destinations: [MIDIDestination] = []

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Text("Spot plays notes over MIDI. It appears to other apps as a MIDI source called “Spot”: choose it as the input of a software instrument in Logic, GarageBand or any synth. You can also send straight to a device below.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Picker("Also send to", selection: $settings.midiDestinationID) {
                        Text("Nothing (Spot source only)").tag(MIDIUniqueID?.none)
                        ForEach(destinations) { destination in
                            Text(destination.name).tag(MIDIUniqueID?.some(destination.id))
                        }
                    }
                    Button("Refresh") { destinations = playback.midiDestinations() }
                }

                Picker("Channel", selection: $settings.midiChannel) {
                    ForEach(1...16, id: \.self) { channel in
                        Text("\(channel)").tag(channel)
                    }
                }

                LabeledContent("Velocity") {
                    Slider(value: Binding(get: { Double(settings.previewVelocity) },
                                          set: { settings.previewVelocity = Int($0) }),
                           in: 1...127)
                    Text("\(settings.previewVelocity)")
                        .monospacedDigit()
                        .frame(width: 32)
                }

                Button("Send test note (middle C)") { playback.sendTestNote() }
            } header: {
                Text("MIDI output")
            }

            Section {
                LabeledContent("Volume") {
                    Slider(value: $settings.metronomeVolume, in: 0...1)
                }
                Picker("Count-in", selection: $settings.countInBars) {
                    Text("None").tag(0)
                    Text("1 bar").tag(1)
                    Text("2 bars").tag(2)
                }
            } header: {
                Text("Metronome")
            }

            if let problem = playback.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { destinations = playback.midiDestinations() }
    }
}
