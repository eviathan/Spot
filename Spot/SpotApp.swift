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
        DocumentGroup(newDocument: SpotDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
