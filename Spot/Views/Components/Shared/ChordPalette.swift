//
//  ChordPalette.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Pick a chord without typing: the key's chords in one click, or a root then a type. Recent picks too.
/// Hands back a chord symbol (e.g. "F#m7b5") that the chord parser reads.
/// When changing a chord, pass it as `current`: its root is picked already and its buttons are highlighted.
struct ChordPalette: View {
    @Environment(LibraryStore.self) private var library

    let key: Key?
    var current: ChordSymbol? = nil
    let onPick: (String) -> Void

    @State private var useSevenths = true
    @State private var root: PitchClass?
    @AppStorage("chordPalette.recent") private var recentStorage = ""

    /// The chord types offered as buttons; everything else is under More.
    private static let commonTypes = [
        "major", "minor", "dominant-7", "major-7", "minor-7", "half-diminished-7",
        "diminished-7", "diminished", "augmented", "sus4", "sus2", "dominant-7-sus4",
        "major-6", "minor-6", "add9", "dominant-9", "major-9", "minor-9",
    ]

    private var recent: [String] {
        recentStorage.split(separator: "|").map(String.init)
    }

    private func pick(_ symbol: String) {
        recentStorage = ([symbol] + recent.filter { $0 != symbol }).prefix(10).joined(separator: "|")
        onPick(symbol)
    }

    /// How to spell a root: from the key if there is one.
    private func spell(_ pitchClass: PitchClass) -> SpelledNote {
        key?.spell(pitchClass) ?? SpelledNote.conventional(pitchClass)
    }

    /// Whether a root and chord type are the chord being changed.
    private func isCurrent(root: PitchClass?, chordId: String) -> Bool {
        guard let current, let root else { return false }
        return current.root.pitchClass == root && current.chord.id == chordId
    }

    private func highlight(_ isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(isOn ? Color.accentColor.opacity(0.4) : .clear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let current {
                HStack(spacing: 6) {
                    Text("Changing")
                        .foregroundStyle(.secondary)
                    Text(current.description)
                        .fontWeight(.bold)
                }
                .font(.callout)
            }

            if let key {
                section("Chords in \(key)") {
                    Picker("", selection: $useSevenths) {
                        Text("Triads").tag(false)
                        Text("Sevenths").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(diatonic(in: key), id: \.symbol) { chord in
                            Button { pick(chord.symbol) } label: {
                                VStack(spacing: 1) {
                                    Text(chord.display).font(.system(size: 13, weight: .semibold))
                                    Text(chord.numeral).font(.caption2).opacity(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .background(highlight(isCurrent(root: chord.root, chordId: chord.chordId)))
                        }
                    }
                }
            }

            section("Root") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 12), spacing: 4) {
                    ForEach(0..<12, id: \.self) { value in
                        let pitchClass = PitchClass(value)
                        Button { root = pitchClass } label: {
                            Text(spell(pitchClass).description)
                                .frame(maxWidth: .infinity, minHeight: 24)
                                .fontWeight(root == pitchClass ? .bold : .regular)
                        }
                        .background(RoundedRectangle(cornerRadius: 4).fill(root == pitchClass ? Color.accentColor.opacity(0.4) : .clear))
                    }
                }
            }

            section(root.map { "Type of \(spell($0)) chord" } ?? "Type (pick a root first)") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(Self.commonTypes, id: \.self) { id in
                        if let chord = library.chord("builtin.chord." + id) {
                            Button { pickType(chord) } label: {
                                Text(chord.displaySymbol.isEmpty ? "maj" : chord.displaySymbol)
                                    .frame(maxWidth: .infinity, minHeight: 24)
                            }
                            .background(highlight(isCurrent(root: root, chordId: chord.id)))
                            .help(chord.name)
                        }
                    }
                }
                .disabled(root == nil)

                // Names the current type when it's one of these
                let otherCurrent = current.flatMap { current in
                    Self.commonTypes.contains { "builtin.chord." + $0 == current.chord.id } ? nil : current.chord
                }
                Menu(otherCurrent.map { "More types (\($0.name))" } ?? "More types") {
                    ForEach(library.chords.sorted { $0.name < $1.name }) { chord in
                        Button {
                            pickType(chord)
                        } label: {
                            if isCurrent(root: root, chordId: chord.id) {
                                Label("\(chord.name)  (\(chord.displaySymbol.isEmpty ? "maj" : chord.displaySymbol))", systemImage: "checkmark")
                            } else {
                                Text("\(chord.name)  (\(chord.displaySymbol.isEmpty ? "maj" : chord.displaySymbol))")
                            }
                        }
                    }
                }
                .disabled(root == nil)
                .fixedSize()
            }

            if !recent.isEmpty {
                section("Recent") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                        ForEach(recent, id: \.self) { symbol in
                            Button(symbol) { pick(symbol) }
                                .background(highlight(symbol == current?.asciiDescription))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear {
            // Changing a chord: start from its root, so picking a type just changes the type
            if let current {
                root = current.root.pitchClass
            }
        }
    }

    private func pickType(_ chord: ChordDefinition) {
        guard let root else { return }
        // Chords the user made may have no symbols yet; fall back to the major triad's empty one
        let symbol = chord.symbols.first ?? ""
        pick(spell(root).asciiDescription + symbol)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// The chords built on each degree of the key's scale.
    private func diatonic(in key: Key) -> [(symbol: String, display: String, numeral: String, root: PitchClass, chordId: String)] {
        let scaleId = key.quality == .major ? "builtin.scale.major" : "builtin.scale.natural-minor"
        guard let scale = library.scale(scaleId) else { return [] }
        return DiatonicChords.build(scale: scale.formula, size: useSevenths ? 4 : 3, chords: library.chords).compactMap { diatonic in
            guard let chord = diatonic.chord else { return nil }
            let root = key.tonic.spelling(diatonic.scaleDegree)
            return (root.asciiDescription + chord.displaySymbol, root.description + chord.displaySymbol, diatonic.numeral,
                    root.pitchClass, chord.id)
        }
    }
}
