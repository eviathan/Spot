//  TabView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct TabView: View {
    @Environment(UIState.self) private var ui
    @Environment(LibraryStore.self) private var library
    
    var backgroundColor: Color { SpotStyle.page }
    
    var body: some View {
        GeometryReader { geometryProxy in
            VStack {
                switch ui.tab {
                    case .Library:
                    LibraryTabView(library: library, geometryProxy: geometryProxy)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .Tab:
                        TabTabView()
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
            .foregroundColor(SpotStyle.text)
        }
    }
}


struct TabView_Previews: PreviewProvider {
    static var previews: some View {
        TabView()
    }
}
