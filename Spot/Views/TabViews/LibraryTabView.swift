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
    
    @State var chordSelection = ChordType.Maj
    
    @State private var selectedNoteCollectionMode: NoteCollectionMode = .Scale
    @State private var treeMenuWidth: CGFloat = 200
    
    private let minWidth: CGFloat = 160
    private let maxWidth: CGFloat = 400
    
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
                        HStack(spacing: 0) {
                            TreeMenuView()
                                .frame(maxWidth: treeMenuWidth)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            
                            // Drag handle
                            // TODO: Make this more general
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 5)
                                .background(Color(hue: 0.64, saturation: 0.30, brightness: 0.24, opacity: 1.00))
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let newWidth = treeMenuWidth + value.translation.width
                                            if newWidth >= minWidth && newWidth <= maxWidth {
                                                treeMenuWidth = newWidth
                                            }
                                        }
                                )
                                .modifier(ResizeCursor())
                        }
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

struct ResizeCursor: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
