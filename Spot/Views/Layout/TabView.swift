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
    let panelBackgroundColor = Color(hue: 1.00, saturation: 0.00, brightness: 0.89, opacity: 1.00)
    
    
    let menuOptions: [NoteCollectionMode] = [.Scales, .Chords]
    
    var body: some View {
        GeometryReader { geometryProxy in
            HStack {
                Text("Tab View")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
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
                .frame(maxWidth: geometryProxy.size.width / 3, maxHeight: .infinity)
                .padding()
                .background(panelBackgroundColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor)
            .foregroundColor(.white)
        }
    }
}


struct TabView_Previews: PreviewProvider {
    static var previews: some View {
        TabView()
    }
}
