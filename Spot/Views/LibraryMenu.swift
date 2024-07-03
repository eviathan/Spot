//
//  LibraryMenu.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct LibraryMenu: View {
    @EnvironmentObject var appState: AppState
    
    @State var buttonSize = CGFloat(50)
    @State var text: String = ""
    
    @FocusState private var isFocused: Bool
    @State private var isSearching = false
    
    let unselectedColor: Color = Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00)
    
    var body: some View {
        HStack {
            Button(action: {appState.toggleLeftSidebar()}) {
                Image(systemName: "sidebar.left")
                    .imageScale(.large)
                    .foregroundColor(appState.displayLeftSidebar ? .white : unselectedColor)
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
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .onHover { hovering in
                        self.isSearching = hovering
                    }
                    .onChange(of: text) { newValue in
                        isSearching = text.count > 0
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
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 2).stroke(isSearching ? .white : unselectedColor))
            .animation(.easeInOut, value: isSearching)
            .frame(maxWidth: 500)
            
            Spacer()
            
            Button(action: {appState.toggleRightSidebar()}) {
                Image(systemName: "sidebar.right")
                    .imageScale(.large)
                    .foregroundColor(appState.displayRightSidebar ? .white : unselectedColor)
                    .padding([.bottom], 2)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: buttonSize, height: buttonSize)
        }
        .background(Color(hue: 0.63, saturation: 0.30, brightness: 0.20, opacity: 1.00))
        //        VStack(alignment: .leading) {
        //            Button(action: {}) {
        //                VStack {
        //                    Image(systemName: "music.note.list")
        //                        .imageScale(.large)
        //                        .foregroundColor(.white)
        //                        .padding([.bottom], 2)
        //                    Text("Scales")
        //                }
        //            }
        //            .buttonStyle(PlainButtonStyle())
        //            .frame(width: buttonSize, height: buttonSize)
        //
        //            Button(action: {}) {
        //                VStack {
        //                    Image(systemName: "rectangle.split.3x1")
        //                        .imageScale(.large)
        //                        .foregroundColor(.white)
        //                        .padding([.bottom], 2)
        //                    Text("Chords")
        //                }
        //            }
        //            .buttonStyle(PlainButtonStyle())
        //            .frame(width: buttonSize, height: buttonSize)
        //
        //            Button(action: {}) {
        //                VStack {
        //                    Image(systemName: "rectangle.split.3x1")
        //                        .imageScale(.large)
        //                        .foregroundColor(.white)
        //                        .padding([.bottom], 2)
        //                    Text("Scales")
        //                }
        //            }
        //            .buttonStyle(PlainButtonStyle())
        //            .frame(width: buttonSize, height: buttonSize)
        //
        //            Button(action: {}) {
        //                VStack {
        //                    Image(systemName: "star")
        //                        .imageScale(.large)
        //                        .foregroundColor(.white)
        //                        .padding([.bottom], 2)
        //                    Text("Favorites")
        //                }
        //            }
        //            .buttonStyle(PlainButtonStyle())
        //            .frame(width: buttonSize, height: buttonSize)
        //        }
        //        .frame(maxHeight: .infinity)
        //    }
    }
}
