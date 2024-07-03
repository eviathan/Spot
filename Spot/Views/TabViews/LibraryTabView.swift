//
//  LibraryTabView.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct LibraryTabView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedNoteCollectionMode: NoteCollectionMode = .Scales
    @State var chordSelection = ChordType.Maj
    
    let geometryProxy: GeometryProxy
    let menuOptions: [NoteCollectionMode] = [.Scales, .Chords]
    let panelBackgroundColor = Color(hue: 1.00, saturation: 0.00, brightness: 0.89, opacity: 1.00)
    
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
                
                VStack() {
                    TableView()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                
                if appState.displayRightSidebar {
                    withAnimation {
                        Text("Library Detail View")
                            .frame(maxWidth: 400, maxHeight: .infinity)
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
}
