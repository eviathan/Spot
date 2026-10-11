//
//  LibraryTransferViews.swift
//  Spot
//

import SwiftUI
import SpotCore

/// Shows what an imported `.spotlib` contains and asks what to do about items that already exist.
struct ImportReviewView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SelectionState.self) private var selection
    @Environment(\.dismiss) private var dismiss

    let pending: PendingImport

    @State private var resolutions: [String: LibraryImport.Resolution] = [:]

    private var plan: LibraryImport {
        pending.plan
    }

    private func count(_ kind: LibraryImport.Item.Kind) -> Int {
        plan.items.filter { $0.kind == kind }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import “\(plan.bundle.bundle.name)”")
                    .font(.title2)
                if let author = plan.bundle.bundle.author {
                    Text("by \(author)").foregroundStyle(.secondary)
                }
                Text("\(count(.scale)) scales, \(count(.chord)) chords, \(count(.shape)) shapes")
                    .foregroundStyle(.secondary)
            }

            if !plan.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Problems in this file").font(.headline)
                    ForEach(plan.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(SpotStyle.warning)
                            .font(.callout)
                    }
                }
            }

            if !plan.conflicts.isEmpty {
                Text("Already in your library").font(.headline)
                List(plan.conflicts) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.isBuiltIn ? "\(item.kind.rawValue.capitalized) · built-in" : item.kind.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: binding(for: item)) {
                            Text("Skip").tag(LibraryImport.Resolution.skip)
                            if !item.isBuiltIn {
                                Text("Replace").tag(LibraryImport.Resolution.replace)
                            }
                            Text("Keep both").tag(LibraryImport.Resolution.keepBoth)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }
                .frame(minHeight: 120, maxHeight: 260)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    library.apply(plan.resolved(resolutions, default: .keepBoth))
                    selection.refreshDefinitions()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.items.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func binding(for item: LibraryImport.Item) -> Binding<LibraryImport.Resolution> {
        Binding(get: { resolutions[item.id] ?? .keepBoth },
                set: { resolutions[item.id] = $0 })
    }
}

/// Chooses what to export before the save panel opens.
struct ExportOptionsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var scope: LibraryExportScope = .mine
    @State private var name = "My Spot library"

    private var preview: LibraryBundle {
        library.exportBundle(scope, name: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export library").font(.title2)

            Form {
                TextField("Name", text: $name)
                Picker("Include", selection: $scope) {
                    Text("My scales, chords and shapes").tag(LibraryExportScope.mine)
                    ForEach(library.allTags, id: \.self) { tag in
                        Text("Tagged “\(tag)”").tag(LibraryExportScope.tag(tag))
                    }
                    Text("Everything, including built-in").tag(LibraryExportScope.everything)
                }
            }

            let bundle = preview
            Text("\(bundle.scales.count) scales, \(bundle.chords.count) chords, \(bundle.shapes.count) shapes")
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    ui.exportFile = LibraryFile(bundle: bundle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bundle.scales.isEmpty && bundle.chords.isEmpty && bundle.shapes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Tags for one library item: remove with ✕, add by typing and pressing Return.
struct TagEditorView: View {
    @Environment(LibraryStore.self) private var library

    let id: String

    @State private var newTag = ""

    var body: some View {
        let tags = library.tags(id)

        HStack(spacing: 6) {
            Image(systemName: "tag")
                .opacity(0.6)

            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                    Button {
                        library.setTags(tags.filter { $0 != tag }, for: id)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.15)))
            }

            TextField("Add tag", text: $newTag)
                .textFieldStyle(.plain)
                .frame(width: 90)
                .onSubmit {
                    library.setTags(tags + [newTag], for: id)
                    newTag = ""
                }

            let suggestions = library.allTags.filter { !tags.contains($0) }
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { tag in
                        Button(tag) { library.setTags(tags + [tag], for: id) }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
        .font(.callout)
    }
}
