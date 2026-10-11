//
//  LibraryItemList.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI

struct LibraryList: View {
    @Environment(UIState.self) private var ui
    @Environment(SelectionState.self) private var selection
    
    var library: LibraryStore
    var selectedId: String
    var onSelect: (_ entry: LibraryEntry) -> Void
    
    var body: some View {
        let withIndex = library.results.enumerated().map({ $0 })
        
        List(withIndex, id: \.element.id) { index, entry in
            LibraryListItem(entry: entry,
                            index: index,
                            isSelected: entry.id == selectedId,
                            isFavourite: library.isFavourite(entry.id),
                            onToggleFavourite: { library.toggleFavourite(entry.id) },
                            onSelect: onSelect)
                .contextMenu { menu(for: entry) }
        }
        .padding(0)
        .scrollIndicators(.never)
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func menu(for entry: LibraryEntry) -> some View {
        Button(library.isFavourite(entry.id) ? "Remove from Favourites" : "Add to Favourites") {
            library.toggleFavourite(entry.id)
        }
        
        if entry.kind != .interval {
            Divider()
            if entry.isEditable {
                Button("Edit…") { ui.definitionEditor = .edit(entry.id) }
            }
            Button(entry.isEditable ? "Duplicate" : "Duplicate to Edit…") {
                if let copy = library.duplicate(entry.id) {
                    ui.definitionEditor = .edit(copy)
                }
            }
            if entry.isEditable {
                Divider()
                Button("Delete", role: .destructive) {
                    library.deleteDefinition(entry.id)
                    selection.refreshDefinitions()
                }
            }
        }
    }
}


struct LibraryListItem: View {
    @State var isHovered: Bool = false
    
    var entry: LibraryEntry
    var index: Int
    var isSelected: Bool
    var isFavourite: Bool
    var onToggleFavourite: () -> Void
    var onSelect: (_ entry: LibraryEntry) -> Void
    
    var backgroundColor: Color {
        let theme = ThemeStore.shared.current
        return isSelected
            ? theme.listSelected
            : isHovered
                ? theme.listHover
                : index % 2 == 0 ? theme.listRow : theme.listAlternateRow
    }
    
    var foregroundColor: Color {
        isHovered || isSelected ? ThemeStore.shared.current.listSelectedText : ThemeStore.shared.current.listText
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleFavourite) {
                Image(systemName: isFavourite ? "heart.fill" : "heart")
                    .foregroundColor(foregroundColor)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 12)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .foregroundColor(foregroundColor)
                Text(entry.detail.isEmpty ? entry.kind.description : "\(entry.kind) · \(entry.detail)")
                    .foregroundColor(foregroundColor.opacity(0.5))
            }
            .frame(width: 200, alignment: .leading) // TODO: Derive this from the longest name in item.name
            
            HStack {
//                Text("TODO: Rest of stuff here")
//                    .foregroundColor(foregroundColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding([.vertical, .horizontal], 12)
        .padding([.horizontal], 12)
        .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: -20))
        .listRowSeparator(.hidden)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .onTapGesture {
            onSelect(entry)
        }
        .onHover { hover in
            isHovered = hover
        }
        .animation(.easeInOut, value: isSelected)
        .animation(.easeInOut, value: isHovered)
        .animation(.easeInOut, value: isFavourite)
    }
}
