//
//  SettingsTabView.swift
//  Spot
//

import SwiftUI
import CoreMIDI
import UniformTypeIdentifiers
import SpotCore

struct SettingsTabView: View {
    @Environment(AudioSettings.self) private var settings
    @Environment(PlaybackController.self) private var playback

    @State private var destinations: [MIDIDestination] = []
    @State private var inputs: [AudioInputDevice] = []
    @State private var choosingSoundFont = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Text("Spot can play notes with its own guitar sound, so you hear them without setting up a synth. It uses macOS's General MIDI instruments, or a SoundFont you choose (for example the free FluidR3 GM, or a guitar SoundFont).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Play with Spot's own sound", isOn: $settings.usesBuiltInSound)
                    .onChange(of: settings.usesBuiltInSound) { playback.soundSettingsChanged() }
                if settings.usesBuiltInSound {
                    LabeledContent("Sound") {
                        HStack {
                            Text(settings.soundFontURL?.deletingPathExtension().lastPathComponent ?? "macOS instruments (built in)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose SoundFont…") { choosingSoundFont = true }
                            if settings.soundFontBookmark != nil {
                                Button("Use Built In") {
                                    settings.soundFontBookmark = nil
                                    playback.soundSettingsChanged()
                                }
                            }
                        }
                    }
                    LabeledContent("Volume") {
                        Slider(value: $settings.builtInSoundVolume, in: 0...1)
                            .onChange(of: settings.builtInSoundVolume) { playback.soundSettingsChanged() }
                    }
                }
                Button("Play test note (middle C)") { playback.sendTestNote() }
            } header: {
                Text("Sound")
            }
            .fileImporter(isPresented: $choosingSoundFont,
                          allowedContentTypes: [UTType(filenameExtension: "sf2"), UTType(filenameExtension: "dls")].compactMap { $0 }) { result in
                guard case .success(let url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                settings.soundFontBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                playback.soundSettingsChanged()
            }

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
                // The count-in is off for now (see PlaybackController.play(from:countIn:))
                // Picker("Count-in", selection: $settings.countInBars) {
                //     Text("None").tag(0)
                //     Text("1 bar").tag(1)
                //     Text("2 bars").tag(2)
                // }
                // .help("Counts in before playback starts, when the metronome is on")
            } header: {
                Text("Metronome")
            }

            Section {
                HStack {
                    Picker("Record from", selection: $settings.inputDeviceID) {
                        Text("System default input").tag(UInt32?.none)
                        ForEach(inputs) { device in
                            Text("\(device.name) (\(device.channelCount) ch)").tag(UInt32?.some(device.id))
                        }
                    }
                    Button("Refresh") { inputs = AudioDevices.inputs() }
                }
                LabeledContent("Latency offset") {
                    Slider(value: $settings.recordingOffsetMs, in: -100...100, step: 1)
                    Text("\(Int(settings.recordingOffsetMs)) ms")
                        .monospacedDigit()
                        .frame(width: 60)
                }
                Text("Takes are moved earlier by the latency the device reports. If they still sound late against the track, increase the offset; if early, decrease it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Recording")
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
        .onAppear {
            destinations = playback.midiDestinations()
            inputs = AudioDevices.inputs()
        }
    }
}
