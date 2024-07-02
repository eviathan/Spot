//
//  LibraryTabView.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject var appState: AppState
    let geometryProxy: GeometryProxy
    @State private var selectedNoteCollectionMode: NoteCollectionMode = .Scales
    
    let menuOptions: [NoteCollectionMode] = [.Scales, .Chords]
    let panelBackgroundColor = Color(hue: 1.00, saturation: 0.00, brightness: 0.89, opacity: 1.00)
    
    var body: some View {
        HStack {
            Text("Something")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                Text("Library Tab View")
                Picker("", selection: $selectedNoteCollectionMode) {
                    ForEach(menuOptions, id: \.self) {
                        Text($0.description)
                            .font(.system(size: 66))
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedNoteCollectionMode) { mode in
                    appState.setNoteCollectionMode(mode: mode)
                }
                Menu {
                    ForEach(ChordType.allCases, id: \.self) { chord in
                        Button(action: { appState.selectedChord = chord }) {
                            Text(chord.description)
                        }
                    }
                    
                } label: {
                    Label(title: {Text(appState.selectedChord.description)}, icon: {})
                }
                HStack {
                    Text("Inversion")
                    Menu {
                        ForEach(ChordType.allCases, id: \.self) { chord in
                            Button(action: { appState.selectedChord = chord }) {
                                Text(chord.description)
                            }
                        }
                        
                    } label: {
                        Label(title: {Text(appState.selectedChord.description)}, icon: {})
                    }
                }
                
                HStack {
                    Text("Variation")
                    Menu {
                        ForEach(ChordType.allCases, id: \.self) { chord in
                            Button(action: { appState.selectedChord = chord }) {
                                Text(chord.description)
                            }
                        }
                        
                    } label: {
                        Label(title: {Text(appState.selectedChord.description)}, icon: {})
                    }
                }
            }
            .frame(maxWidth: geometryProxy.size.width / 3, maxHeight: .infinity)
            .padding()
            .background(panelBackgroundColor)
        }
    }
}
