//
//  LibraryItemList.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI

struct LibraryList: View {
    var library: Library
    var onSelect: (_ item: LibraryItem) -> Void
    var currentSelectionMode: NoteCollectionMode
    var currentSelectionScale: ScaleType?
    var currentSelectionChord: ChordType?
    
    
    var body: some View {
        let withIndex = library.items.enumerated().map({ $0 })
        
        List(withIndex, id: \.element.id) { index, item in
            LibraryListItem(index: index,
                            item: item,
                            currentSelectionMode: currentSelectionMode,
                            currentSelectionScale: currentSelectionScale,
                            currentSelectionChord: currentSelectionChord,
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
    
    var index: Int
    var item: LibraryItem
    
    var currentSelectionMode: NoteCollectionMode
    var currentSelectionScale: ScaleType?
    var currentSelectionChord: ChordType?
    
    var onSelect: (_ item: LibraryItem) -> Void
    
    var backgroundColor: Color {
        isSelected
            ? Color(hue: 0.63, saturation: 0.35, brightness: 0.24, opacity: 1.00)
            : isHovered
                ? Color(hue: 0.75, saturation: 0.01, brightness: 0.30, opacity: 1.00)
                : index % 2 == 0
                    ? Color(hue: 0.00, saturation: 0.00, brightness: 1.00, opacity: 1.00)
                    : Color(hue: 0.75, saturation: 0.01, brightness: 0.80, opacity: 0.30)
    }
    
    var isSelected: Bool {
        switch currentSelectionMode {
        case .Scale:
            return currentSelectionScale == item.scaleType
        case .Chord:
            return currentSelectionChord == item.chordType
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .foregroundColor(isHovered || isSelected ? .white : .black)
                Text(item.type.description)
                    .foregroundColor((isHovered || isSelected ? Color.white : Color.black).opacity(0.5))
            }
            
            HStack {
                Text("Rest of stuff here")
                    .foregroundColor(isHovered || isSelected ? .white : .black)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                onSelect(item)
            }
            .onHover { hover in
                isHovered = hover
            }
        }
        .padding([.vertical, .horizontal], 12)
        .padding([.horizontal], 12)
        .listRowInsets(EdgeInsets(top: 0, leading: -20, bottom: 0, trailing: -20))
        .listRowSeparator(.hidden)
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .onTapGesture {
            onSelect(item)
        }
        .animation(.easeInOut, value: isSelected)
        .animation(.easeInOut, value: isHovered)
    }
}
