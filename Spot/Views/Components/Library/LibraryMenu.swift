//
//  LibraryMenu.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct LibraryMenu: View {
    @Environment(UIState.self) private var ui
    @Environment(LibraryStore.self) private var library
    
    @State var buttonSize = CGFloat(50)
    @State var text: String = ""
    
    @FocusState private var isFocused: Bool
    @State private var isSearching = false
    
    var unselectedColor: Color { SpotStyle.dimmed }
    
    var body: some View {
        HStack {
            Button(action: {ui.displayLeftSidebar.toggle()}) {
                Image(systemName: "sidebar.left")
                    .imageScale(.large)
                    .foregroundColor(ui.displayLeftSidebar ? .white : unselectedColor)
                    .padding([.bottom], 2)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: buttonSize, height: buttonSize)
            
            Spacer()
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .imageScale(.large)
                    .foregroundColor(isSearching ? .white : unselectedColor)
                    .padding([.bottom], 2)
                    .animation(.easeInOut, value: isSearching)
                
                TextField("", text: $text)
                    .accentColor(.red)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .onHover { hovering in
                        self.isSearching = text.count > 0 || hovering
                    }
                    .onChange(of: text) {
                        isSearching = text.count > 0
                        library.query = text
                    }
                
                Button(action: {text = ""}) {
                    Image(systemName: "xmark")
                        .imageScale(.large)
                        .foregroundColor(isSearching ? .white : unselectedColor)
                        .padding([.bottom], 2)
                        .animation(.easeInOut, value: isSearching)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(text.count > 0 ? 1 : 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 2).stroke(isSearching ? .white : unselectedColor))
            .animation(.easeInOut, value: isSearching)
            .frame(maxWidth: 500)
            
            Spacer()
            
            Menu {
                Button("New Scale…") { ui.definitionEditor = .new(.scale) }
                Button("New Chord…") { ui.definitionEditor = .new(.chord) }
                Divider()
                Button("Import Library…") { ui.isImporting = true }
                Button("Export Library…") { ui.isChoosingExport = true }
            } label: {
                Image(systemName: "plus")
                    .imageScale(.large)
                    .foregroundColor(.white)
            }
            // Drawn by SwiftUI, so the label keeps its colour (a borderless-button menu is drawn by AppKit, which tints
            // the image grey whatever it's given)
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("New scale or chord, import or export")

            Button(action: {ui.displayRightSidebar.toggle()}) {
                Image(systemName: "sidebar.right")
                    .imageScale(.large)
                    .foregroundColor(ui.displayRightSidebar ? .white : unselectedColor)
                    .padding([.bottom], 2)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: buttonSize, height: buttonSize)
        }
        .background(ThemeStore.shared.current.card)
    }
}
