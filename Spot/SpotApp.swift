//
//  SpotApp.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

@main
struct SpotApp: App {
    var body: some Scene {
        WindowGroup() {
            LayoutView()
                .frame(minWidth: 1280, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: false))
    }
}
