//
//  AppState.swift
//  Spot
//
//  Created by Brian Williams on 16/04/2024.
//

import Foundation

class AppState: ObservableObject {
    @Published var instrument: InstrumentType = .guitar
    @Published var selectedNote: Note = .E
    @Published var inversion: Inversion = .Root
    @Published var hideUnrelatedNotes: Bool = false
    @Published var labelMode: FretLabelType = .note
    @Published var highlightedMode: Bool = true
    @Published var noteCollectionMode: NoteCollectionMode = .Scales
    
    @Published var selectedChord: ChordType = .Maj
    @Published var selectedScale: ScaleType = .Major
    
    
    
    func toggleHideUnrelatedNotes() {
        hideUnrelatedNotes.toggle()
    }
    
    func toggleHighlightedMode() {
        highlightedMode.toggle()
    }
    
    func toggleLabelMode() {
        switch labelMode {
        case .note:
            labelMode = .interval(note: selectedNote)
        case .interval(_):
            labelMode = .note
        }
    }
    
    func setNoteCollectionMode(mode: NoteCollectionMode) {
        noteCollectionMode = mode
    }
}
