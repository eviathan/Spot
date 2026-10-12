//
//  Theme.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//
import SwiftUI
import Foundation
import Observation
import SpotCore

/// Every colour in the app, from a theme file (see SpotCore's `ThemeFile`, and default.yaml for what each key
/// is). A theme can leave colours out: they come from the default theme.
final class Theme {
    let name: String
    private let colors: [String: RGBA]

    init(_ definition: ThemeDefinition = BuiltInThemes.defaultTheme, fallback: ThemeDefinition = BuiltInThemes.defaultTheme) {
        name = definition.name
        colors = fallback.colors.merging(definition.colors) { _, mine in mine }
    }

    /// A colour by its key ("fretboard.strings"); magenta if a key is missing altogether, so it shows up.
    func color(_ key: String) -> Color {
        colors[key].map(Color.init) ?? Color(red: 1, green: 0, blue: 1)
    }

    private func rgba(_ key: String) -> RGBA? {
        colors[key]
    }

    // MARK: Interface

    var page: Color { color("interface.page") }
    var panel: Color { color("interface.panel") }
    var panelHover: Color { color("interface.panelHover") }
    var card: Color { color("interface.card") }
    var header: Color { color("interface.header") }
    var headerText: Color { color("interface.headerText") }
    var footer: Color { color("interface.footer") }
    var text: Color { color("interface.text") }
    var secondaryText: Color { color("interface.secondaryText") }
    var dimmed: Color { color("interface.dimmed") }
    var accent: Color { color("interface.accent") }
    var warning: Color { color("interface.warning") }
    var error: Color { color("interface.error") }
    var control: Color { color("interface.control") }
    var divider: Color { color("interface.divider") }
    var border: Color { color("interface.border") }

    // MARK: The Library's list

    var listBackground: Color { color("list.background") }
    var listRow: Color { color("list.row") }
    var listAlternateRow: Color { color("list.alternateRow") }
    var listHover: Color { color("list.hover") }
    var listSelected: Color { color("list.selected") }
    var listText: Color { color("list.text") }
    var listSelectedText: Color { color("list.selectedText") }

    // MARK: The fretboard

    var fretboardBackground: Color { color("fretboard.background") }
    /// Fret numbers, and text on light notes.
    var fretboardColor: Color { color("fretboard.ink") }
    var stringColor: Color { color("fretboard.strings") }
    var fretColor: Color { color("fretboard.frets") }
    var fretMarkerColor: Color { color("fretboard.inlays") }
    var nutColor: Color { color("fretboard.nut") }
    var defaultMarkerColor: Color { color("fretboard.note") }
    var openMarkerColor: Color { color("fretboard.openNote") }

    // MARK: Intervals and roles

    static let intervalKeys = ["root", "m2", "M2", "m3", "M3", "P4", "TT", "P5", "m6", "M6", "m7", "M7"]

    /// By semitones above the root.
    var intervalColors: [Color] {
        Theme.intervalKeys.map { color("intervals." + $0) }
    }

    /// An interval's colour by semitones above the root (any number: it's taken round the octave).
    func intervalColor(_ semitones: Int) -> Color {
        color("intervals." + Theme.intervalKeys[Theme.octave(semitones)])
    }

    /// An interval's colour on a dark background: the root (black on the fretboard) in the text colour.
    func chipColour(_ degree: SpotCore.Degree) -> Color {
        let semitones = Theme.octave(degree.pitchClassOffset)
        return semitones == 0 ? text : intervalColor(semitones)
    }

    /// Readable text on a solid interval colour: white on dark ones, black on light ones.
    func textColor(onInterval semitones: Int) -> Color {
        isDark(intervalKey: Theme.intervalKeys[Theme.octave(semitones)]) ? .white : .black
    }

    /// Whether an interval's colour is dark enough to want white text on it.
    func isDarkInterval(_ semitones: Int) -> Bool {
        isDark(intervalKey: Theme.intervalKeys[Theme.octave(semitones)])
    }

    private func isDark(intervalKey: String) -> Bool {
        // White text wins below about 0.18
        (luminance(of: "intervals." + intervalKey) ?? 1) < 0.18
    }

    /// A colour's relative luminance (WCAG), 0 for black to 1 for white.
    private func luminance(of key: String) -> Double? {
        guard let rgba = rgba(key) else { return nil }
        let channel = { (value: Double) in value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(rgba.red) + 0.7152 * channel(rgba.green) + 0.0722 * channel(rgba.blue)
    }

    /// The piano's white keys: the fretboard's note colour (light in a light theme, dark in a dark one).
    var pianoWhiteKey: Color { defaultMarkerColor }

    /// The piano's black keys, darker than the white ones whatever the theme: the darker of the fretboard's ink and
    /// its background (the ink is light in a dark theme, for text on the dark neck).
    var pianoBlackKey: Color {
        (luminance(of: "fretboard.ink") ?? 0) <= (luminance(of: "fretboard.background") ?? 1) ? fretboardColor : fretboardBackground
    }

    private static func octave(_ semitones: Int) -> Int {
        ((semitones % 12) + 12) % 12
    }

    /// Chord Practice colours by what a note does over the chord.
    var chordToneColor: Color { color("roles.chordTone") }
    var tensionColor: Color { color("roles.tension") }
    var avoidColor: Color { color("roles.avoid") }

    // MARK: The sequencer

    var chordClip: Color { color("sequencer.chord") }
    var invalidChord: Color { color("sequencer.invalidChord") }
    var pattern: Color { color("sequencer.pattern") }
    var nextChord: Color { color("sequencer.nextChord") }
    var waveform: Color { color("sequencer.waveform") }
    var playhead: Color { color("sequencer.playhead") }
    var loop: Color { color("sequencer.loop") }
    var warpMarker: Color { color("sequencer.warpMarker") }
    var activeWarpMarker: Color { color("sequencer.activeWarpMarker") }
    var songMarker: Color { color("sequencer.songMarker") }
    var take: Color { color("sequencer.take") }

    // MARK: The tab

    var tabSelection: Color { color("tab.selection") }
    var tabPlayhead: Color { color("tab.playhead") }
    var tabChordName: Color { color("tab.chordName") }
    var tabError: Color { color("tab.error") }
}

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

/// The themes on offer (Spot's own and any imported) and the one in use. Imported themes are YAML files kept in
/// Spot's Application Support folder, under Themes.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    struct Entry: Identifiable, Hashable {
        /// "builtin:default", or "user:<file name>".
        let id: String
        let definition: ThemeDefinition
        /// Where an imported one is kept (nil for Spot's own).
        let url: URL?

        var isBuiltIn: Bool { url == nil }
    }

    private(set) var themes: [Entry] = []
    private(set) var current = Theme()
    private(set) var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "theme") }
    }

    private init() {
        selectedID = UserDefaults.standard.string(forKey: "theme") ?? "builtin:default"
        reload()
    }

    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Spot/Themes", isDirectory: true)
    }

    /// Reads the themes again (Spot's own, then the imported ones by name), and applies the chosen one.
    func reload() {
        var entries = BuiltInThemes.all().map { Entry(id: "builtin:" + $0.id, definition: $0.theme, url: nil) }
        let files = (try? FileManager.default.contentsOfDirectory(at: ThemeStore.folder, includingPropertiesForKeys: nil)) ?? []
        let imported = files.filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }.compactMap { url -> Entry? in
            guard let text = try? String(contentsOf: url, encoding: .utf8), let theme = try? ThemeFile.parse(text) else { return nil }
            return Entry(id: "user:" + url.lastPathComponent, definition: theme, url: url)
        }
        entries += imported.sorted { $0.definition.name.localizedStandardCompare($1.definition.name) == .orderedAscending }
        themes = entries
        apply()
    }

    func select(_ id: String) {
        selectedID = id
        apply()
    }

    private func apply() {
        let entry = themes.first { $0.id == selectedID } ?? themes.first
        current = Theme(entry?.definition ?? BuiltInThemes.defaultTheme)
    }

    /// Checks a theme file reads, then keeps a copy (replacing an earlier one of the same file name) and uses it.
    func importTheme(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        _ = try ThemeFile.parse(text)
        try FileManager.default.createDirectory(at: ThemeStore.folder, withIntermediateDirectories: true)
        let name = url.pathExtension.lowercased() == "yml" ? url.deletingPathExtension().lastPathComponent + ".yaml" : url.lastPathComponent
        let destination = ThemeStore.folder.appendingPathComponent(name)
        try text.write(to: destination, atomically: true, encoding: .utf8)
        reload()
        select("user:" + name)
    }

    func remove(_ entry: Entry) {
        guard let url = entry.url else { return }
        try? FileManager.default.removeItem(at: url)
        if selectedID == entry.id { selectedID = "builtin:default" }
        reload()
    }

    /// The theme in use as a YAML file: every colour, laid out and explained like the default, to start a new one from.
    func exportText(named name: String? = nil) -> String {
        let defaults = BuiltInThemes.defaultTheme
        let entry = themes.first { $0.id == selectedID }
        let colors = defaults.colors.merging(entry?.definition.colors ?? [:]) { _, mine in mine }
        let layout: (order: [String], comments: [String: String]) = BuiltInThemes.text("default").map(ThemeFile.layout(of:)) ?? ([], [:])
        let header = """
        # Spot theme
        #
        # Colours are #RRGGBB, #RRGGBBAA, rgb(r, g, b) or rgba(r, g, b, a) (channels 0–255, alpha 0–1).
        # A theme only needs the colours it changes: anything left out comes from the default theme.

        """
        return header + ThemeFile.write(ThemeDefinition(name: name ?? (entry?.definition.name ?? "Default") + " (Copy)", colors: colors),
                                        keyOrder: layout.order, comments: layout.comments)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
