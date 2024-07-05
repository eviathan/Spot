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

class TreeItem: Identifiable {
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

struct TreeMenuView: View {
    
    @State var data: [TreeItem] = [
        TreeItem(name: "Sort", type: .folder, children: [
            TreeItem(name: "Name", type: .item),
            TreeItem(name: "Type", type: .item),
        ]),
        
        TreeItem(name: "Types", type: .folder, children: [
            TreeItem(name: "Scales", type: .item),
            TreeItem(name: "Chords", type: .item),
            TreeItem(name: "Interval", type: .item),
        ]),
        
        TreeItem(name: "Test", type: .folder, children: [
            TreeItem(name: "Test Child really really really really long", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
        ])
    ]
    
    var body: some View {
        ZStack {
            List(Array(data.enumerated()), id: \.offset) { index, item in
                TreeMenuSection(item: item, index: index)
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
    var item: TreeItem
    var index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TreeMenuItem(item: item, index: index)
            
            ForEach(Array(item.children.enumerated()), id: \.offset) { childIndex, child in
                TreeMenuItem(item: child, index: childIndex)
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
    
    var foregroundColor: Color {
        !isHovered ? .white : .black
    }
    
    var image: String {
        switch item.type {
            case .folder:
                return "folder.fill"
            case .item:
                return "doc.fill"
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
                Image(systemName: "chevron.down")
                    .padding(.trailing, 6)
            }
            
            Image(systemName: image)
                .padding(.trailing, 6)
            
            Text(item.name)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, index == 0 && item.type == .folder ? 16 : 8)
        .padding(.bottom, 8)
        .padding(.horizontal, 8)
        .padding(.leading, leftPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color(hue: 0.63, saturation: 0.28, brightness: 0.20, opacity: 1.00) : Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00))
        .clipped()
        .onHover { hovered in
            isHovered = hovered
        }
    }
}


//                HStack(spacing: 0) {
//                    Image(systemName: "textformat.alt")
//                        .padding(.trailing, 6)
//
//                    Text(child.name)
//                        .foregroundColor(.white)
//                        .lineLimit(1)
//                        .truncationMode(.tail)
//                }
//                .padding(.leading, 32)
//                .padding([.vertical], 6)
//                .foregroundColor(.white)
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .background(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00)) // Ensure background color matches
//                .clipped() // Ensure no overflow
