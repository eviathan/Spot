//
//  ModeSwitcher.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct ModeSwitcher: View {
    @EnvironmentObject var appState: AppState
    
    let unselectedColor: Color = Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00)
    
    var body: some View {
        Button(action: { appState.tab = .Library }) {
            Image(systemName: "rectangle.split.3x1")
                .imageScale(.large)
                .foregroundColor(appState.tab == .Library ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: { appState.tab = .Editor }) {
            Image(systemName: "rectangle.split.3x3")
                .imageScale(.large)
                .foregroundColor(appState.tab == .Editor ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: { appState.tab = .Sequence }) {
            Image(systemName: "text.justify")
                .imageScale(.large)
                .foregroundColor(appState.tab == .Sequence ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: { appState.tab = .Settings }) {
            Image(systemName: "slider.horizontal.3")
                .imageScale(.large)
                .foregroundColor(appState.tab == .Settings ? .white : unselectedColor)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
    }
}
