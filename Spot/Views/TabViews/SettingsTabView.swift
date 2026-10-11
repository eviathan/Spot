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
                        .foregroundStyle(SpotStyle.warning)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(SpotStyle.warning.opacity(0.12)))
                }

                AppearanceSection()

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
                                .foregroundStyle(SpotStyle.secondary)
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
        .background(SpotStyle.page)
        .foregroundStyle(.white)
        // Menus, sliders and switches drawn for a dark background, in the transport's green
        .environment(\.colorScheme, .dark)
        .tint(SpotStyle.accent)
        .onAppear {
            destinations = playback.midiDestinations()
            inputs = AudioDevices.inputs()
        }
    }
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
                .foregroundStyle(SpotStyle.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                // Rows, with a hairline between them
                _VariadicView.Tree(DividedRows()) {
                    content()
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(SpotStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.06)))
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(SpotStyle.secondary)
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
                    .fill(SpotStyle.divider)
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
            .foregroundStyle(SpotStyle.secondary)
            .frame(width: 52, alignment: .trailing)
    }
}

/// Themes: Spot's own and any imported, each a card with a strip of its colours. Click one to use it.
private struct AppearanceSection: View {
    @Environment(ThemeStore.self) private var themes
    @State private var problem: String?

    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPEARANCE")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(SpotStyle.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(themes.themes) { entry in
                        ThemeCard(entry: entry, isSelected: entry.id == themes.selectedID) {
                            withAnimation(.easeInOut(duration: 0.25)) { themes.select(entry.id) }
                        } onRemove: {
                            themes.remove(entry)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("Import Theme…", action: importTheme)
                    Button("Export Current Theme…", action: exportTheme)
                    Spacer()
                    Button("Show Themes Folder") {
                        try? FileManager.default.createDirectory(at: ThemeStore.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ThemeStore.folder)
                    }
                    .help("Themes are YAML files: put one here and reopen Settings, or import it")
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(SpotStyle.warning)
                        .font(.callout)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(SpotStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SpotStyle.border))
            Text("A theme is a YAML file of colours (#RRGGBB, #RRGGBBAA, rgb() or rgba()), and only needs the ones it changes. Export the current theme for a file with every colour explained, to start one of your own.")
                .font(.callout)
                .foregroundStyle(SpotStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
        .onAppear { themes.reload() }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.yaml, UTType(filenameExtension: "yml"), .plainText].compactMap { $0 }
        panel.prompt = "Import"
        panel.message = "Choose a theme (a YAML file of colours)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try themes.importTheme(from: url)
            problem = nil
        } catch {
            problem = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.yaml]
        let name = themes.themes.first { $0.id == themes.selectedID }?.definition.name ?? "Theme"
        panel.nameFieldStringValue = "\(name) Copy.yaml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try themes.exportText(named: "\(name) Copy").write(to: url, atomically: true, encoding: .utf8)
            problem = nil
        } catch {
            problem = "Couldn't save the theme: \(error.localizedDescription)"
        }
    }
}

/// A theme to pick: its name and a strip of its colours (the page, the header, the neck, then the intervals).
private struct ThemeCard: View {
    let entry: ThemeStore.Entry
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let theme = Theme(entry.definition)
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // A little picture of the window: header, neck with notes, page
                VStack(spacing: 0) {
                    theme.header.frame(height: 8)
                    ZStack {
                        theme.fretboardBackground
                        HStack(spacing: 3) {
                            ForEach([0, 3, 4, 7, 10, 11, 2, 5, 9], id: \.self) { semitones in
                                Circle()
                                    .fill(theme.intervalColor(semitones))
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                    .frame(height: 28)
                    theme.page.frame(height: 14)
                        .overlay(alignment: .leading) {
                            Capsule().fill(theme.accent).frame(width: 26, height: 4).padding(.leading, 8)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08)))

                HStack(spacing: 6) {
                    Text(entry.definition.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if !entry.isBuiltIn {
                        Text("Imported")
                            .font(.system(size: 10))
                            .foregroundStyle(SpotStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SpotStyle.accent)
                    }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? SpotStyle.control : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? SpotStyle.accent.opacity(0.7) : SpotStyle.border,
                                                                     lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !entry.isBuiltIn {
                Button("Remove Theme", role: .destructive, action: onRemove)
            }
        }
        .help(entry.isBuiltIn ? entry.definition.name : "\(entry.definition.name) (imported; right-click to remove)")
    }
}
