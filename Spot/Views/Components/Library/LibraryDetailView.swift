//
//  LibraryDetailView.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import SwiftUI
import SpotCore

struct LibraryDetailView: View {
    @Environment(SelectionState.self) private var selection
    @Environment(LibraryStore.self) private var library
    @Environment(UIState.self) private var ui

    private var shapeSystemBinding: Binding<String> {
        Binding(get: { selection.shapeSystem ?? "" },
                set: { selection.shapeSystem = $0.isEmpty ? nil : $0 })
    }

    private var isEditable: Bool {
        library.entry(selection.selectedId)?.isEditable == true
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(selection.title)
                    .font(.title)
                    .multilineTextAlignment(.center)

                if selection.kind != .interval {
                    definitionActions
                }

                TagEditorView(id: selection.selectedId)

                Divider().padding(.horizontal, 40)

                if selection.shapeDraft != nil {
                    ShapeDraftControls()
                } else {
                    shapeNavigator
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)

            IntervalMatrixView()
            IntervalBannerView(degrees: selection.formula.degrees)
        }
    }

    private var definitionActions: some View {
        HStack(spacing: 12) {
            if isEditable {
                Button("Edit…") { ui.definitionEditor = .edit(selection.selectedId) }
            }
            Button(isEditable ? "Duplicate" : "Duplicate to edit…") {
                if let copy = library.duplicate(selection.selectedId) {
                    ui.definitionEditor = .edit(copy)
                }
            }
            if isEditable {
                Button("Delete", role: .destructive) {
                    library.deleteDefinition(selection.selectedId)
                    selection.refreshDefinitions()
                }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var shapeNavigator: some View {
        if let shape = selection.currentShape, let index = selection.currentShapeIndex {
            HStack(spacing: 12) {
                Button(action: selection.previousShape) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Previous shape (⌘[)")

                VStack(spacing: 2) {
                    Text(shape.name)
                    Text("\(shape.system) · \(index + 1) of \(selection.shapes.count)")
                        .font(.caption)
                        .opacity(0.6)
                }
                .frame(minWidth: 260)

                Button(action: selection.nextShape) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .help("Next shape (⌘])")
            }
        }

        if selection.shapeSystems.count > 1 {
            Picker("Shapes", selection: shapeSystemBinding) {
                Text("All shapes").tag("")
                ForEach(selection.shapeSystems, id: \.self) { system in
                    Text(system).tag(system)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260)
        }

        if selection.kind != .interval {
            HStack(spacing: 12) {
                Button("New shape") { selection.startNewShape(copyingCurrent: false) }
                if selection.currentShape != nil {
                    Button("Copy shape") { selection.startNewShape(copyingCurrent: true) }
                }
                if let shape = selection.currentShape, library.isUserShape(shape.id) {
                    Button("Edit shape") { selection.editCurrentShape() }
                    Button("Delete shape", role: .destructive) { selection.deleteCurrentShape() }
                }
            }
            .controlSize(.small)
        }
    }
}

/// Name, type and save/cancel for a shape being drawn on the fretboard.
private struct ShapeDraftControls: View {
    @Environment(SelectionState.self) private var selection

    var body: some View {
        if let draft = selection.shapeDraft {
            VStack(spacing: 10) {
                Text(draft.editingId == nil ? "Drawing a new shape" : "Editing shape")
                    .font(.headline)
                Text("Click notes on the fretboard to add or remove them. Right-click a note to set its finger.")
                    .font(.caption)
                    .opacity(0.7)
                    .multilineTextAlignment(.center)

                Form {
                    TextField("Name", text: Binding(get: { selection.shapeDraft?.name ?? "" },
                                                    set: { selection.shapeDraft?.name = $0 }))
                    TextField("Group", text: Binding(get: { selection.shapeDraft?.system ?? "" },
                                                     set: { selection.shapeDraft?.system = $0 }))
                    if selection.kind == .chord {
                        Picker("Played as", selection: Binding(get: { selection.shapeDraft?.kind ?? .chord },
                                                              set: { selection.shapeDraft?.kind = $0 })) {
                            Text("Chord").tag(ShapeKind.chord)
                            Text("Arpeggio").tag(ShapeKind.scale)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .frame(maxWidth: 320)

                HStack(spacing: 12) {
                    Text("\(draft.notes.count) notes")
                        .font(.caption)
                        .opacity(0.7)
                    Button("Cancel") { selection.cancelShapeDraft() }
                    Button("Save shape") { selection.saveShapeDraft() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.notes.isEmpty)
                }
                .controlSize(.small)
            }
        }
    }
}
