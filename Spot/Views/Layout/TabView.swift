//  TabView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct TabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedNoteCollectionMode: NoteCollectionMode = .Scales

    let backgroundColor = Color(hue: 0.62, saturation: 0.38, brightness: 0.24, opacity: 1.00)
    let panelBackgroundColor = Color(hue: 0.63, saturation: 0.35, brightness: 0.44, opacity: 1.00)
    
    
    let menuOptions: [NoteCollectionMode] = [.Scales, .Chords]
    
    var body: some View {
        HStack {
            VStack {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(panelBackgroundColor)
            
            
            Text("Tab View")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .foregroundColor(.white)
    }
}


struct TabView_Previews: PreviewProvider {
    static var previews: some View {
        TabView()
    }
}
