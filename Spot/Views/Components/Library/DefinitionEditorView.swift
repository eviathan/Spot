//
//  DefinitionEditorView.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Sheet for making or editing your own scale or chord.
struct DefinitionEditorView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SelectionState.self) private var selection
    @Environment(\.dismiss) private var dismiss

    let request: DefinitionEditorRequest

    @State private var kind: LibraryEntryKind = .scale
    @State private var id = LibraryStore.newUserId()
    @State private var isNew = true
    @State private var name = ""
    @State private var formulaText = ""
    @State private var aliasesText = ""
    @State private var family = ""
    @State private var parent: ScaleDefinition.ModeParent?
    @State private var symbolsText = ""
    @State private var optional: Set<Degree> = []
    @State private var tags: [String] = []

    private var formula: Formula? {
        Formula(formulaText)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var scaleDraft: ScaleDefinition? {
        formula.map {
            ScaleDefinition(id: id, name: trimmedName, aliases: list(aliasesText), formula: $0,
                            family: family.isEmpty ? nil : family, parent: parent)
        }
    }

    private var chordDraft: ChordDefinition? {
        formula.map {
            ChordDefinition(id: id, name: trimmedName, symbols: list(symbolsText), formula: $0,
                            optional: optional.filter($0.degrees.contains))
        }
    }

    private var issues: [String] {
        var issues: [String] = []
        if trimmedName.isEmpty {
            issues.append("Give it a name.")
        }
        guard formula != nil else {
            issues.append("The formula should be degrees separated by spaces, like 1 b3 5 b7.")
            return issues
        }
        if kind == .chord && list(symbolsText).isEmpty {
            issues.append("Add at least one chord symbol, e.g. m7.")
        }
        let found = kind == .scale ? library.issues(for: scaleDraft!) : library.issues(for: chordDraft!)
        // Issues start with the id ("user.x: ..."), which means nothing to the reader
        return issues + found.map { $0.replacingOccurrences(of: "\(id): ", with: "").replacingOccurrences(of: id, with: "this") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New \(kind.description.lowercased())" : "Edit \(kind.description.lowercased())")
                .font(.title2)

            Form {
                if isNew {
                    Picker("Type", selection: $kind) {
                        Text("Scale").tag(LibraryEntryKind.scale)
                        Text("Chord").tag(LibraryEntryKind.chord)
                    }
                    .pickerStyle(.segmented)
                }

                TextField("Name", text: $name)
                TextField("Formula", text: $formulaText, prompt: Text(kind == .scale ? "1 2 b3 4 5 6 b7" : "1 b3 5 b7"))

                if kind == .scale {
                    TextField("Other names", text: $aliasesText, prompt: Text("Comma separated"))
                    HStack {
                        TextField("Family", text: $family, prompt: Text("e.g. Major modes"))
                        Menu("") {
                            ForEach(library.scaleFamilies, id: \.self) { existing in
                                Button(existing) { family = existing }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                    }
                    if let parent, let parentScale = library.scale(parent.id) {
                        HStack {
                            Text("Mode \(parent.degree) of \(parentScale.name)")
                                .foregroundStyle(.secondary)
                            Button("Unlink") { self.parent = nil }
                        }
                    }
                } else {
                    TextField("Symbols", text: $symbolsText, prompt: Text("Comma separated, first is shown: m7, min7, -7"))
                    if let formula, formula.degrees.count > 1 {
                        HStack {
                            Text("Optional")
                                .foregroundStyle(.secondary)
                            ForEach(formula.degrees.dropFirst(), id: \.self) { degree in
                                Toggle(degree.prettyDescription, isOn: Binding(
                                    get: { optional.contains(degree) },
                                    set: { if $0 { optional.insert(degree) } else { optional.remove(degree) } }
                                ))
                                .toggleStyle(.button)
                            }
                        }
                    }
                }
            }

            if let formula {
                IntervalBannerView(degrees: formula.degrees)
                    .cornerRadius(4)
            }

            ForEach(issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SpotStyle.warning)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!issues.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: load)
    }

    private func load() {
        switch request {
        case .new(let newKind):
            kind = newKind == .chord ? .chord : .scale
        case .edit(let existingId):
            isNew = false
            id = existingId
            if let scale = library.scale(existingId) {
                kind = .scale
                name = scale.name
                formulaText = scale.formula.description
                aliasesText = scale.aliases.joined(separator: ", ")
                family = scale.family ?? ""
                parent = scale.parent
            } else if let chord = library.chord(existingId) {
                kind = .chord
                name = chord.name
                formulaText = chord.formula.description
                symbolsText = chord.symbols.joined(separator: ", ")
                optional = chord.optional
            }
        }
    }

    private func save() {
        if kind == .scale, let scale = scaleDraft {
            library.save(scale)
        } else if let chord = chordDraft {
            library.save(chord)
        }
        selection.refreshDefinitions()
        if let entry = library.entry(id) {
            selection.select(entry, in: library)
        }
        dismiss()
    }
}
