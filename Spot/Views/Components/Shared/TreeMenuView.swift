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
    var id = UUID() // Add id property to conform to Identifiable
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
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
            TreeItem(name: "Test Child", type: .item),
        ]),
        
        TreeItem(name: "", type: .folder)
    ]
    
    var body: some View {
        ZStack {
            List(data) { item in
                TreeMenuItem(item: item)
                    .listRowBackground(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
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

struct TreeMenuItem: View {
    @State var isHovered: Bool = false
    
    var item: TreeItem
    
    var foregroundColor: Color {
        !isHovered ? .white : .black
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "chevron.down")
                    .padding(.trailing, 6)
                
                Image(systemName: "folder.fill")
                    .padding(.trailing, 6)
                
                Text(item.name)
                    .foregroundColor(.white)
            }
            .padding([.vertical], 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00))
            .clipped()
            
            ForEach(item.children) { child in
                HStack(spacing: 0) {
                    Image(systemName: "textformat.alt")
                        .padding(.trailing, 6)
                    
                    Text(child.name)
                        .foregroundColor(.white)
                }
                .padding(.leading, 32)
                .padding([.vertical], 4)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00)) // Ensure background color matches
                .clipped() // Ensure no overflow
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(hue: 0.64, saturation: 0.32, brightness: 0.24, opacity: 1.00)) // Ensure background color matches
        .clipped() // Ensure no overflow
    }
}
