//
//  LibraryTabView.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct LibraryTabView: View {
    @Environment(UIState.self) private var ui
    @Environment(SelectionState.self) private var selection
    var library: LibraryStore
    
    @State private var treeMenuWidth: CGFloat = 200
    
    private let minWidth: CGFloat = 160
    private let maxWidth: CGFloat = 400
    
    let geometryProxy: GeometryProxy
    let panelBackgroundColor = Color(hue: 1.00, saturation: 0.00, brightness: 0.89, opacity: 1.00)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryMenu()
            HStack(spacing: 0) {
                if ui.displayLeftSidebar {
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
                            selectedId: selection.selectedId,
                            onSelect: onSelect)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                if ui.displayRightSidebar {
                    withAnimation {
                        LibraryDetailView()
                            .frame(minWidth: 450, maxWidth: 450, maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .background(.gray)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut, value: ui.displayLeftSidebar)
            .animation(.easeInOut, value: ui.displayRightSidebar)
        }
    }
    
    func onSelect(_ entry: LibraryEntry) {
        selection.select(entry, in: library)
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
