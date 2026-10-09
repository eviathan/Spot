//
//  UIState.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

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

struct PendingImport: Identifiable {
    let id = UUID()
    let plan: LibraryImport
}

/// Window layout and open sheets. Sidebars are saved between launches.
@Observable
final class UIState {
    var tab: TabViewType = .Library
    var definitionEditor: DefinitionEditorRequest?
    var isImporting = false
    var pendingImport: PendingImport?
    var isChoosingExport = false
    var exportFile: LibraryFile?
    var isExporting = false
    var errorMessage: String?
    var displayLeftSidebar: Bool {
        didSet { defaults.set(displayLeftSidebar, forKey: "ui.displayLeftSidebar") }
    }
    var displayRightSidebar: Bool {
        didSet { defaults.set(displayRightSidebar, forKey: "ui.displayRightSidebar") }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayLeftSidebar = defaults.object(forKey: "ui.displayLeftSidebar") as? Bool ?? true
        displayRightSidebar = defaults.object(forKey: "ui.displayRightSidebar") as? Bool ?? true
    }
}
