//
//  LibraryTabView.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var library: Library
    
    @State private var selectedNoteCollectionMode: NoteCollectionMode = .Scale
    @State var chordSelection = ChordType.Maj
    
    let geometryProxy: GeometryProxy
    let menuOptions: [NoteCollectionMode] = [.Scale, .Chord]
    let panelBackgroundColor = Color(hue: 1.00, saturation: 0.00, brightness: 0.89, opacity: 1.00)
    
    func convertSearchResults(result: FuzzySrchResult) -> DataModel {
        let item = library.items[result.index]
        return DataModel(name: item.name, type: item.type.description, item: item)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryMenu()
            HStack(spacing: 0) {
                if appState.displayLeftSidebar {
                    withAnimation {
                        Text("Filter List")
                            .frame(maxWidth: 200)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                
                LibraryList(library: library,
                            onSelect: onSelect,
                            currentSelectionMode: appState.noteCollectionMode,
                            currentSelectionScale: appState.selectedScale,
                            currentSelectionChord: appState.selectedChord)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                if appState.displayRightSidebar {
                    withAnimation {
                        LibraryDetailView()
                            .frame(maxWidth: 450, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .background(.gray)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut, value: appState.displayLeftSidebar)
            .animation(.easeInOut, value: appState.displayRightSidebar)
        }
    }
    
    func onSelect(_ item: LibraryItem) {
        appState.noteCollectionMode = item.type
        
        if let scaleType = item.scaleType {
            appState.selectedScale = scaleType
        }
        
        if let chordType = item.chordType {
            appState.selectedChord = chordType
        }        
    }
}
