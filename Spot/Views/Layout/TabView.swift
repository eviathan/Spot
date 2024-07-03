//  TabView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct TabView: View {
    @EnvironmentObject var appState: AppState
    
    let backgroundColor = Color(hue: 0.62, saturation: 0.38, brightness: 0.24, opacity: 1.00)
    
    var body: some View {
        GeometryReader { geometryProxy in
            VStack {
                switch appState.tab {
                    case .Library:
                        LibraryTabView(geometryProxy: geometryProxy)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .Editor:
                        EditorTabView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .Sequence:
                        SequenceTabView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .Settings:
                        Text("Settings")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor)
            .foregroundColor(.white)
        }
    }
}


struct TabView_Previews: PreviewProvider {
    static var previews: some View {
        TabView()
    }
}
