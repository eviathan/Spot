//  TabView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct TabView: View {
    @Environment(UIState.self) private var ui
    @Environment(LibraryStore.self) private var library
    
    let backgroundColor = Color(hue: 0.62, saturation: 0.38, brightness: 0.24, opacity: 1.00)
    
    var body: some View {
        GeometryReader { geometryProxy in
            VStack {
                switch ui.tab {
                    case .Library:
                    LibraryTabView(library: library, geometryProxy: geometryProxy)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .Practice:
                        ChordPracticeTabView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .Sequence:
                        SequenceTabView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .Settings:
                        SettingsTabView()
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
