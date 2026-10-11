//
//  SettingsTabView.swift
//  Spot
//

import SwiftUI
import CoreMIDI
import UniformTypeIdentifiers
import SpotCore

/// Sound, MIDI, metronome and recording, in the app's own look: dark cards on the navy page, a label on the left
/// and its control on the right, with what each section is for underneath in dimmed text.
struct SettingsTabView: View {
    @Environment(AudioSettings.self) private var settings
    @Environment(PlaybackController.self) private var playback

    @State private var destinations: [MIDIDestination] = []
    @State private var inputs: [AudioInputDevice] = []
    @State private var choosingSoundFont = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                    .padding(.bottom, 4)

                if let problem = playback.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                }

                SettingsSection("Sound",
                                note: "Spot plays notes with its own guitar sound, so you hear them without setting up a synth. It uses macOS's General MIDI instruments, or a SoundFont you choose (for example the free FluidR3 GM, or a guitar SoundFont).") {
                    SettingsRow("Spot's own sound") {
                        Toggle("", isOn: $settings.usesBuiltInSound)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: settings.usesBuiltInSound) { playback.soundSettingsChanged() }
                    }
                    if settings.usesBuiltInSound {
                        SettingsRow("Instruments") {
                            Text(settings.soundFontURL?.deletingPathExtension().lastPathComponent ?? "macOS (built in)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(SettingsStyle.secondary)
                            if settings.soundFontBookmark != nil {
                                Button("Use Built In") {
                                    settings.soundFontBookmark = nil
                                    playback.soundSettingsChanged()
                                }
                            }
                            Button("Choose SoundFont…") { choosingSoundFont = true }
                        }
                        SettingsRow("Volume") {
                            Slider(value: $settings.builtInSoundVolume, in: 0...1)
                                .frame(maxWidth: 260)
                                .onChange(of: settings.builtInSoundVolume) { playback.soundSettingsChanged() }
                        }
                    }
                    SettingsRow("Test") {
                        Button("Play Middle C") { playback.sendTestNote() }
                    }
                }
                .fileImporter(isPresented: $choosingSoundFont,
                              allowedContentTypes: [UTType(filenameExtension: "sf2"), UTType(filenameExtension: "dls")].compactMap { $0 }) { result in
                    guard case .success(let url) = result else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    settings.soundFontBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    playback.soundSettingsChanged()
                }

                SettingsSection("MIDI Output",
                                note: "Spot also plays everything over MIDI. It appears to other apps as a MIDI source called “Spot”: choose it as the input of a software instrument in Logic, GarageBand or any synth, or send straight to a device here.") {
                    SettingsRow("Also send to") {
                        Picker("", selection: $settings.midiDestinationID) {
                            Text("Nothing (Spot source only)").tag(MIDIUniqueID?.none)
                            ForEach(destinations) { destination in
                                Text(destination.name).tag(MIDIUniqueID?.some(destination.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        Button {
                            destinations = playback.midiDestinations()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Look for MIDI devices again")
                    }
                    SettingsRow("Channel") {
                        Picker("", selection: $settings.midiChannel) {
                            ForEach(1...16, id: \.self) { channel in
                                Text("\(channel)").tag(channel)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                    SettingsRow("Velocity") {
                        Slider(value: Binding(get: { Double(settings.previewVelocity) },
                                              set: { settings.previewVelocity = Int($0) }),
                               in: 1...127)
                            .frame(maxWidth: 260)
                        SettingsValue("\(settings.previewVelocity)")
                    }
                }

                SettingsSection("Metronome") {
                    SettingsRow("Volume") {
                        Slider(value: $settings.metronomeVolume, in: 0...1)
                            .frame(maxWidth: 260)
                    }
                    // The count-in is off for now (see PlaybackController.play(from:countIn:))
                }

                SettingsSection("Recording",
                                note: "Takes are moved earlier by the latency the device reports. If they still sound late against the track, increase the offset; if early, decrease it.") {
                    SettingsRow("Record from") {
                        Picker("", selection: $settings.inputDeviceID) {
                            Text("System default input").tag(UInt32?.none)
                            ForEach(inputs) { device in
                                Text("\(device.name) (\(device.channelCount) ch)").tag(UInt32?.some(device.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        Button {
                            inputs = AudioDevices.inputs()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Look for input devices again")
                    }
                    SettingsRow("Latency offset") {
                        Slider(value: $settings.recordingOffsetMs, in: -100...100, step: 1)
                            .frame(maxWidth: 260)
                        SettingsValue("\(Int(settings.recordingOffsetMs)) ms")
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(SettingsStyle.page)
        .foregroundStyle(.white)
        // Menus, sliders and switches drawn for a dark background, in the transport's green
        .environment(\.colorScheme, .dark)
        .tint(SettingsStyle.accent)
        .onAppear {
            destinations = playback.midiDestinations()
            inputs = AudioDevices.inputs()
        }
    }
}

/// The colours the rest of Spot uses.
private enum SettingsStyle {
    /// The page (as behind the tab and the Library).
    static let page = Color(hue: 0.62, saturation: 0.38, brightness: 0.24)
    /// A card on it (as the Library's menu).
    static let card = Color(hue: 0.63, saturation: 0.30, brightness: 0.19)
    /// Headings and notes (as the dimmed footer icons, a little lighter to read as text).
    static let secondary = Color(hue: 0.62, saturation: 0.22, brightness: 0.70)
    static let divider = Color.white.opacity(0.07)
    /// As the play button while playing.
    static let accent = Color(red: 0.55, green: 0.85, blue: 0.45)
}

/// A titled card of rows, with an optional note under it.
private struct SettingsSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.note = note
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(SettingsStyle.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                // Rows, with a hairline between them
                _VariadicView.Tree(DividedRows()) {
                    content()
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(SettingsStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06)))
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(SettingsStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }
}

/// Puts a hairline between a section's rows.
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        ForEach(children) { child in
            child
            if child.id != children.last?.id {
                Rectangle()
                    .fill(SettingsStyle.divider)
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
    }
}

/// A label on the left, its control on the right.
private struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    init(_ label: String, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.control = control
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                control()
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}

/// A slider's value, beside it.
private struct SettingsValue: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(SettingsStyle.secondary)
            .frame(width: 52, alignment: .trailing)
    }
}
