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
    @State private var isEditing = false
    
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
            TextField("Search ...", text: $text)
                .padding(7)
                .padding(.horizontal, 12)
                .background(Color(.black))
                .cornerRadius(18)
                .padding(.horizontal, 10)
                .onTapGesture {
                    self.isEditing = true
                }
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
