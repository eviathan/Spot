//
//  LibraryDetailView.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import SwiftUI

struct LibraryDetailView: View {
    @Environment(SelectionState.self) private var selection
    
    @State private var selectedInversion = "Ionian"
    
    let inversions = ["Ionian", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Aeolian", "Locrian"]
    
    private var shapeSystemBinding: Binding<String> {
        Binding(get: { selection.shapeSystem ?? "" },
                set: { selection.shapeSystem = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(selection.title)
                    .font(.title)

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
            }
            .frame(maxHeight: .infinity)

//            VStack {
//                Text("Library Detail View")
                
//                Picker("Inversion", selection: $selectedInversion) {
//                    ForEach(inversions, id: \.self) {
//                            Text($0)
//                        }
//                }
//                .pickerStyle(DefaultPickerStyle())
//                
//                Dropdown()
//                
//                Text("TODO: Edit button link to edit screen")
//            }
//            .padding(24)
//            .frame(maxHeight: .infinity)
            
            IntervalMatrixView()
            IntervalBannerView(degrees: selection.formula.degrees)
        }
    }
}
