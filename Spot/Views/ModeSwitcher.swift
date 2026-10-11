//
//  ModeSwitcher.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct ModeSwitcher: View {
    @Environment(UIState.self) private var ui
    
    let unselectedColor: Color = Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00)
    
    var body: some View {
        Button(action: { ui.tab = .Sequence }) {
            Image(systemName: "text.justify")
                .imageScale(.large)
                .foregroundColor(ui.tab == .Sequence ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: { ui.tab = .Tab }) {
            Image(systemName: "rectangle.split.3x3")
                .imageScale(.large)
                .foregroundColor(ui.tab == .Tab ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help("Tab")
        
        Button(action: { ui.tab = .Library }) {
            Image(systemName: "rectangle.split.3x1")
                .imageScale(.large)
                .foregroundColor(ui.tab == .Library ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: { ui.tab = .Settings }) {
            Image(systemName: "slider.horizontal.3")
                .imageScale(.large)
                .foregroundColor(ui.tab == .Settings ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
    }
}
