//
//  SpotApp.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

@main
struct SpotApp: App {
    var appState = AppState()

    var body: some Scene {
        WindowGroup() {
            LayoutView()
                .frame(minWidth: 1280, minHeight: 800)
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(UnifiedWindowToolbarStyle(showsTitle: false))
        .commands {
            // TODO: Move these state changes into a method on appState and call that instead
             CommandMenu("Inversions") {
                Button("Root Inversion") { appState.inversion = .Root }
                 .keyboardShortcut("1")
                 .disabled(!appState.highlightedMode)
                 
                Button("1st Inversion") { appState.inversion = .First }
                 .keyboardShortcut("2")
                 .disabled(!appState.highlightedMode)
                 
                Button("2nd Inversion") { appState.inversion = .Second }
                 .keyboardShortcut("3")
                 .disabled(!appState.highlightedMode)
                 
                Button("3rd Inversion") { appState.inversion = .Third }
                 .keyboardShortcut("4")
                 .disabled(!appState.highlightedMode)
                 
                Button("4th Inversion") {  appState.inversion = .Fourth }
                 .keyboardShortcut("5")
                 .disabled(!appState.highlightedMode)
                 
                Button("5th Inversion") {  appState.inversion = .Fifth }
                 .keyboardShortcut("6")
                 .disabled(!appState.highlightedMode)
                 
                Button("6th Inversion") {  appState.inversion = .Sixth }
                 .keyboardShortcut("7")
                 .disabled(!appState.highlightedMode)
             }
            
            CommandGroup(before: .toolbar) {
                Button(appState.hideUnrelatedNotes ? "Show Unrelated Notes" : "Hide Unrelated Notes") {
                    appState.toggleHideUnrelatedNotes()
                }
                .keyboardShortcut("U", modifiers: [.command])
                Button("Toggle Label Mode") {
                    appState.toggleLabelMode()
                }
                .keyboardShortcut("I", modifiers: [.command])
                Button("Toggle Highlighted Mode") {
                    appState.toggleHighlightedMode()
                }
                .keyboardShortcut("O", modifiers: [.command])
            }
       }
    }
}
