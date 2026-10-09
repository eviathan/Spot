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
                            TreeMenuView(data: sidebarItems)
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
    
    /// Filter and sort options for the left sidebar.
    var sidebarItems: [TreeItem] {
        let showAll = library.kindFilter == nil && library.familyFilter == nil && !library.favouritesOnly
        
        let show = TreeItem(name: "Show", type: .folder, children: [
            TreeItem(name: "Everything", type: .item, isSelected: showAll) { library.clearFilters() },
            TreeItem(name: "Favourites", type: .item, isSelected: library.favouritesOnly) {
                library.favouritesOnly.toggle()
            },
        ] + [LibraryEntryKind.scale, .chord, .interval].map { kind in
            TreeItem(name: "\(kind)s", type: .item, isSelected: library.kindFilter == kind && library.familyFilter == nil) {
                library.familyFilter = nil
                library.kindFilter = library.kindFilter == kind ? nil : kind
            }
        })
        
        let families = TreeItem(name: "Scale families", type: .folder, children: library.scaleFamilies.map { family in
            TreeItem(name: family, type: .item, isSelected: library.familyFilter == family) {
                if library.familyFilter == family {
                    library.familyFilter = nil
                    library.kindFilter = nil
                } else {
                    library.familyFilter = family
                    library.kindFilter = .scale
                }
            }
        })
        
        let sort = TreeItem(name: "Sort", type: .folder, children: [
            TreeItem(name: "Library order", type: .item, isSelected: library.sortOrder == .library) { library.sortOrder = .library },
            TreeItem(name: "Name", type: .item, isSelected: library.sortOrder == .name) { library.sortOrder = .name },
        ])
        
        // TODO: Tags section once tags can be added (Plan.md, step 4d)
        return [show, families, sort]
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
