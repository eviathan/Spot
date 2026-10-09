//
//  LibraryItemList.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI

struct LibraryList: View {
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
        }
        .padding(0)
        .scrollIndicators(.never)
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .frame(maxWidth: .infinity)
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
        isSelected
            ? Color(hue: 0.63, saturation: 0.35, brightness: 0.24, opacity: 1.00)
            : isHovered
                ? Color(hue: 0.75, saturation: 0.01, brightness: 0.30, opacity: 1.00)
                : index % 2 == 0
                    ? Color(hue: 0.00, saturation: 0.00, brightness: 1.00, opacity: 1.00)
                    : Color(hue: 0.75, saturation: 0.01, brightness: 0.80, opacity: 0.30)
    }
    
    var foregroundColor: Color {
        isHovered || isSelected ? .white : .black
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
