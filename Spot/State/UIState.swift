//
//  UIState.swift
//  Spot
//

import Foundation
import Observation
import UniformTypeIdentifiers
import SpotCore

/// The one Open panel the window can show. SwiftUI on macOS only honours one file importer per window
/// when they're nested, so every kind of opening goes through this.
enum OpenPanel: Equatable {
    case library
    case sequence
    case audio
    case relinkAudio
    case tab

    var contentTypes: [UTType] {
        switch self {
        case .library: return [.spotLibrary, .json]
        case .sequence: return [.spotSequence]
        case .tab: return [.spotTab]
        case .audio, .relinkAudio: return [.audio]
        }
    }
}

/// The one Save panel the window can show (see `OpenPanel`).
enum SavePanel: Equatable {
    case library
    case sequence
    case tab
}

/// Something that replaces the open tab, held back while asking whether to save it first.
enum TabAction: Equatable {
    case new
    case open
    case openURL(URL)
    case openRecent(TabSession.Recent)
    case close
}

/// Which scale or chord the definition editor is working on.
enum DefinitionEditorRequest: Identifiable {
    case new(LibraryEntryKind)
    case edit(String)

    var id: String {
        switch self {
        case .new(let kind): return "new-\(kind)"
        case .edit(let id): return id
        }
    }
}

/// Something that replaces the open sequence, held back while asking whether to save it first.
enum SequenceAction: Equatable {
    case new
    case open
    case openURL(URL)
    case openRecent(SequenceSession.Recent)
    case close
    /// Start recording once the sequence has been saved (takes live in its package).
    case startRecording
}

struct PendingImport: Identifiable {
    let id = UUID()
    let plan: LibraryImport
}

/// Window layout and open sheets. Sidebars are saved between launches.
@Observable
final class UIState {
    var tab: TabViewType = .Library
    var definitionEditor: DefinitionEditorRequest?
    var openPanel: OpenPanel? {
        didSet { if let openPanel { lastOpenPanel = openPanel } }
    }
    /// Which panel was showing, still known after it closes (when its result arrives).
    private(set) var lastOpenPanel: OpenPanel = .library
    var savePanel: SavePanel? {
        didSet { if let savePanel { lastSavePanel = savePanel } }
    }
    private(set) var lastSavePanel: SavePanel = .library
    
    var isImporting: Bool {
        get { openPanel == .library }
        set { setOpenPanel(.library, newValue) }
    }
    var pendingImport: PendingImport?
    var isChoosingExport = false
    var exportFile: LibraryFile?
    var isExporting: Bool {
        get { savePanel == .library }
        set { setSavePanel(.library, newValue) }
    }
    var errorMessage: String?
    var isOpeningSequence: Bool {
        get { openPanel == .sequence }
        set { setOpenPanel(.sequence, newValue) }
    }
    var isImportingAudio: Bool {
        get { openPanel == .audio }
        set { setOpenPanel(.audio, newValue) }
    }
    var isRelinkingAudio: Bool {
        get { openPanel == .relinkAudio }
        set { setOpenPanel(.relinkAudio, newValue) }
    }
    var isSavingSequenceAs: Bool {
        get { savePanel == .sequence }
        set { setSavePanel(.sequence, newValue) }
    }
    
    private func setOpenPanel(_ panel: OpenPanel, _ show: Bool) {
        if show {
            openPanel = panel
        } else if openPanel == panel {
            openPanel = nil
        }
    }
    
    private func setSavePanel(_ panel: SavePanel, _ show: Bool) {
        if show {
            savePanel = panel
        } else if savePanel == panel {
            savePanel = nil
        }
    }
    /// Waiting on "save changes to Untitled?" for a tab.
    var pendingTabAction: TabAction?
    var tabActionAfterSave: TabAction?
    /// Waiting on "save changes to Untitled?"
    var pendingSequenceAction: SequenceAction?
    /// Carry on with this once Save As finishes.
    var sequenceActionAfterSave: SequenceAction?
    var displayLeftSidebar: Bool {
        didSet { defaults.set(displayLeftSidebar, forKey: "ui.displayLeftSidebar") }
    }
    var displayRightSidebar: Bool {
        didSet { defaults.set(displayRightSidebar, forKey: "ui.displayRightSidebar") }
    }
    /// Just the fretboard: the tab's content below it is hidden (except on Settings, which has no fretboard).
    var isFretboardOnly: Bool {
        didSet { defaults.set(isFretboardOnly, forKey: "ui.isFretboardOnly") }
    }
    var showsFretboardOnly: Bool {
        isFretboardOnly && tab != .Settings
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayLeftSidebar = defaults.object(forKey: "ui.displayLeftSidebar") as? Bool ?? true
        displayRightSidebar = defaults.object(forKey: "ui.displayRightSidebar") as? Bool ?? true
        isFretboardOnly = defaults.bool(forKey: "ui.isFretboardOnly")
    }
    
    /// Does `action` now, or first asks whether to save an unsaved tab.
    func requestTabAction(_ action: TabAction, session: TabSession) {
        if action != .open && session.needsSaveBeforeClosing {
            pendingTabAction = action
        } else {
            perform(action, session: session)
        }
    }

    func perform(_ action: TabAction, session: TabSession) {
        do {
            switch action {
            case .new:
                session.newScore()
                tab = .Tab
            case .open:
                openPanel = .tab
            case .openURL(let url):
                try session.open(url)
                tab = .Tab
            case .openRecent(let recent):
                try session.open(recent)
                tab = .Tab
            case .close:
                session.close()
            }
        } catch {
            errorMessage = "Couldn't open the tab: \(error.localizedDescription)"
        }
    }

    /// Does `action` now, or first asks whether to save an unsaved sequence.
    func requestSequenceAction(_ action: SequenceAction, session: SequenceSession) {
        if action != .open && session.needsSaveBeforeClosing {
            pendingSequenceAction = action
        } else {
            perform(action, session: session)
        }
    }
    
    func perform(_ action: SequenceAction, session: SequenceSession) {
        do {
            switch action {
            case .new:
                session.newSequence()
                tab = .Sequence
            case .open:
                isOpeningSequence = true
            case .openURL(let url):
                try session.open(url)
                tab = .Sequence
            case .openRecent(let recent):
                try session.open(recent)
                tab = .Sequence
            case .close:
                session.close()
            case .startRecording:
                try session.startRecording()
            }
        } catch {
            errorMessage = "Couldn't open the sequence: \(error.localizedDescription)"
        }
    }
}
