//
//  TreeMenuView.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI

enum TreeItemType {
    case folder
    case item
}

class TreeItemGroup: Identifiable {
    var id = UUID()
    var name: String
    var type: TreeItemType
    var children: [TreeItem] = []
    
    init(name: String, type: TreeItemType, children: [TreeItem] = []) {
        self.name = name
        self.type = type
        self.children = children
    }
}

class TreeItem: Identifiable {
    var id = UUID()
    var name: String
    var type: TreeItemType
    var children: [TreeItem] = []
    var isSelected: Bool
    var action: (() -> Void)?
    
    init(name: String, type: TreeItemType, children: [TreeItem] = [], isSelected: Bool = false, action: (() -> Void)? = nil) {
        self.name = name
        self.type = type
        self.children = children
        self.isSelected = isSelected
        self.action = action
    }
}

struct TreeMenuView: View {
    
    var data: [TreeItem]
    
    var body: some View {
        ZStack {
            List(Array(data.enumerated()), id: \.offset) { index, item in
                TreeMenuSection(item: item, index: index, isLastSection: { index in data.count -  1 == index})
                    .listRowBackground(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00))
                    .listRowInsets(EdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -8))
            }
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 0)
            .scrollIndicators(.never)
            .listStyle(.plain)
            .listRowSeparator(.hidden)
        }
        .background(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TreeMenuSection: View {
    @State var isOpen: Bool = true
    
    var item: TreeItem
    var index: Int
    var isLastSection: (Int) -> Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TreeMenuItem(item: item, index: index, isSelected: isOpen)
                .onTapGesture {
                    isOpen.toggle()
                }
            
            if(isOpen) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { childIndex, child in
                    TreeMenuItem(item: child, index: childIndex, isLastItem: {childIndex in
                        isLastSection(index) &&
                        item.children.count - 1 == childIndex
                    })
                    .contentShape(Rectangle())
                    .onTapGesture {
                        child.action?()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00))
        .clipped()
    }
}

struct TreeMenuItem: View {
    @State var isHovered: Bool = false
    
    var item: TreeItem
    var index: Int
    var isLastItem: (Int) -> Bool = {_ in false}
    var isSelected: Bool = false
    
    var foregroundColor: Color {
        !isHovered ? .white : .black
    }
    
    var image: String {
        switch item.type {
            case .folder:
                return "folder.fill"
            case .item:
                return item.isSelected ? "checkmark.circle.fill" : "circle"
        }
    }
    
    var leftPad: CGFloat {
        switch item.type {
            case .folder:
                return 8
            case .item:
                return 42
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if(item.type == .folder) {
                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .padding(.trailing, 6)
            }
            
            Image(systemName: image)
                .padding(.trailing, 6)
            
            Text(item.name)
                .foregroundColor(.white)
                .fontWeight(item.isSelected ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, index == 0 && item.type == .folder ? 16 : 8)
        .padding(.bottom, isLastItem(index) ? 24 : 8)
        .padding(.trailing, 3)
        .padding(.leading, leftPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color(hue: 0.63, saturation: 0.28, brightness: 0.20, opacity: 1.00) : Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00))
        .clipped()
        .onHover { hovered in
            isHovered = hovered
        }
    }
}
