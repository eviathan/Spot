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
    @Environment(PlaybackController.self) private var playback
    @Environment(TransportState.self) private var transport

    private var shapeSystemBinding: Binding<String> {
        Binding(get: { selection.shapeSystem ?? "" },
                set: { selection.shapeSystem = $0.isEmpty ? nil : $0 })
    }

    private var isEditable: Bool {
        library.entry(selection.selectedId)?.isEditable == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // What it is, what you can do with it, its tags
                VStack(alignment: .leading, spacing: 10) {
                    SpotHeading("\(selection.kind)")
                    Text(selection.title)
                        .font(.system(size: 26, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    rootPicker
                    if selection.kind != .interval {
                        definitionActions
                    }
                    TagEditorView(id: selection.selectedId)
                        .foregroundStyle(SpotStyle.secondary)
                }

                if selection.shapeDraft != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        SpotHeading("Shape")
                        ShapeDraftControls()
                            .spotCard()
                    }
                } else if selection.currentShape != nil || selection.kind != .interval {
                    VStack(alignment: .leading, spacing: 8) {
                        SpotHeading("Shape")
                        shapeNavigator
                            .spotCard()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SpotHeading("Intervals")
                    IntervalBannerView(degrees: selection.formula.degrees)
                }

                IntervalMatrixView()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .background(SpotStyle.card)
        .overlay(alignment: .leading) {
            Rectangle().fill(SpotStyle.border).frame(width: 1)
        }
        .environment(\.colorScheme, .dark)
        .tint(SpotStyle.accent)
    }

    /// The Library's own root (and, for a scale, the key it's the scale of): apart from the sequence's key, in the
    /// footer, so looking something up here never changes a sequence.
    private var rootPicker: some View {
        HStack(spacing: 8) {
            Button { selection.transposeRoot(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(SpotStyle.control))
            }
            .buttonStyle(.plain)
            .help("Root down a semitone")

            // Every root, the current one ticked
            Menu {
                Picker("Root", selection: Binding(get: { selection.root.value }, set: { selection.root = PitchClass($0) })) {
                    ForEach(0..<12, id: \.self) { value in
                        Text(SpelledNote.conventional(PitchClass(value)).description).tag(value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(selection.spelledRoot.description)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 26)
                    .background(Capsule().fill(SpotStyle.control))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("The root here in the Library (the sequence's key is in the footer)")

            Button { selection.transposeRoot(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(SpotStyle.control))
            }
            .buttonStyle(.plain)
            .help("Root up a semitone")

            // // A scale: which key's (major, minor or a mode), picking that scale
            // if selection.kind == .scale {
            //     Menu {
            //         ForEach([KeyQuality.major, .minor, .dorian, .phrygian, .lydian, .mixolydian, .locrian], id: \.self) { quality in
            //             Button {
            //                 if let scale = library.scale(quality.scaleId) { selection.selectScale(scale) }
            //             } label: {
            //                 if selection.keyQuality == quality {
            //                     Label(quality.name.capitalized, systemImage: "checkmark")
            //                 } else {
            //                     Text(quality.name.capitalized)
            //                 }
            //             }
            //         }
            //     } label: {
            //         Text(selection.keyQuality?.name.capitalized ?? "Key…")
            //             .font(.system(size: 13))
            //             .padding(.horizontal, 10)
            //             .frame(minHeight: 26)
            //             .background(Capsule().fill(SpotStyle.control))
            //     }
            //     .menuStyle(.button)
            //     .buttonStyle(.plain)
            //     .menuIndicator(.hidden)
            //     .fixedSize()
            //     .help("Show this root's major or minor scale, or one of its modes")
            // }
        }
    }

    private var definitionActions: some View {
        HStack(spacing: 8) {
            if isEditable {
                Button("Edit…") { ui.definitionEditor = .edit(selection.selectedId) }
            }
            Button(isEditable ? "Duplicate" : "Duplicate to Edit…") {
                if let copy = library.duplicate(selection.selectedId) {
                    ui.definitionEditor = .edit(copy)
                }
            }
            if isEditable {
                Button("Delete") {
                    library.deleteDefinition(selection.selectedId)
                    selection.refreshDefinitions()
                }
                .buttonStyle(SpotPillButtonStyle(isDestructive: true))
            }
        }
        .buttonStyle(SpotPillButtonStyle())
    }

    @ViewBuilder
    private var shapeNavigator: some View {
        VStack(spacing: 14) {
            if let shape = selection.currentShape, let index = selection.currentShapeIndex {
                HStack(spacing: 10) {
                    Button(action: selection.previousShape) {
                        Image(systemName: "chevron.left")
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(SpotStyle.control))
                    }
                    .buttonStyle(.plain)
                    .help("Previous shape (⌘[)")

                    VStack(spacing: 3) {
                        Text(shape.name)
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(shape.system) · \(index + 1) of \(selection.shapes.count)")
                            .font(.caption)
                            .foregroundStyle(SpotStyle.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: selection.nextShape) {
                        Image(systemName: "chevron.right")
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(SpotStyle.control))
                    }
                    .buttonStyle(.plain)
                    .help("Next shape (⌘])")

                    // Play, or stop while it's playing
                    let isPlaying = playback.audition != nil
                    Button {
                        if isPlaying {
                            playback.stopAudition()
                        } else if let placement = shape.placements(root: selection.root, on: selection.fretboard).first {
                            playback.audition(shape, placement: placement, on: selection.fretboard, clock: transport.clock)
                        }
                    } label: {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(SpotStyle.accent))
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "Stop (⌘↩)" : "Hear this shape (⌘↩). ⌥-click a note on the fretboard to hear just that note.")
                }
            } else {
                Text("No shapes yet")
                    .foregroundStyle(SpotStyle.secondary)
            }

            if selection.shapeSystems.count > 1 {
                Picker("Shapes", selection: shapeSystemBinding) {
                    Text("All shapes").tag("")
                    ForEach(selection.shapeSystems, id: \.self) { system in
                        Text(system).tag(system)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            if selection.kind != .interval {
                HStack(spacing: 8) {
                    Button("New Shape") { selection.startNewShape(copyingCurrent: false) }
                    if selection.currentShape != nil {
                        Button("Copy Shape") { selection.startNewShape(copyingCurrent: true) }
                    }
                    if let shape = selection.currentShape, library.isUserShape(shape.id) {
                        Button("Edit Shape") { selection.editCurrentShape() }
                        Button("Delete") { selection.deleteCurrentShape() }
                            .buttonStyle(SpotPillButtonStyle(isDestructive: true))
                    }
                }
                .buttonStyle(SpotPillButtonStyle())
            }
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
                    .foregroundStyle(SpotStyle.secondary)
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

                HStack(spacing: 8) {
                    Text("\(draft.notes.count) notes")
                        .font(.caption)
                        .foregroundStyle(SpotStyle.secondary)
                    Spacer()
                    Button("Cancel") { selection.cancelShapeDraft() }
                        .buttonStyle(SpotPillButtonStyle())
                    Button("Save Shape") { selection.saveShapeDraft() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.notes.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }
}
