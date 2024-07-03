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
    @Published var labelMode: FretLabelType = .note // TODO: Deprecate this if I cant fix it in place of the display intervals implementation below
    @Published var highlightedMode: Bool = true
    @Published var isolateInversion: Bool = true
    @Published var displayIntervals: Bool = true
    @Published var displayLeftSidebar: Bool = false
    @Published var displayRightSidebar: Bool = false
    @Published var noteCollectionMode: NoteCollectionMode = .Scale
    @Published var selectedChord: ChordType = .Maj
    @Published var selectedScale: ScaleType = .Major
    @Published var tab: TabViewType = .Library
    @Published var library: Library = Library()
    @Published var theme: Theme = Theme()
    
    func toggleHideUnrelatedNotes() {
        hideUnrelatedNotes.toggle()
    }
    
    func toggleHighlightedMode() {
        highlightedMode.toggle()
    }
    
    func toggleIsolatedInversion() {
        isolateInversion.toggle()
    }
    
    func toggleShowIntervalMode() {
        displayIntervals.toggle()
    }
    
    func setNoteCollectionMode(mode: NoteCollectionMode) {
        noteCollectionMode = mode
    }
    
    func toggleLeftSidebar() {
        displayLeftSidebar.toggle()
    }
    
    func toggleRightSidebar() {
        displayRightSidebar.toggle()
    }
    
    func getSelectedIntervals() -> [Interval] {
        return noteCollectionMode == .Scale
            ? selectedScale.intervals
            : selectedChord.intervals
    }
    
    func getSelectedName() -> String {
        return noteCollectionMode == .Scale
            ? selectedScale.description
            : selectedChord.description
    }
}
