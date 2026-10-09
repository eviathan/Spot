//
//  DisplaySettings.swift
//  Spot
//

import Foundation
import Observation

enum MarkerLabel: String, CaseIterable {
    case interval
    case note
    /// Suggested finger for notes in the selected shape; interval for the rest.
    case finger
    
    var next: MarkerLabel {
        let all = MarkerLabel.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// How the instrument is drawn. Saved between launches.
@Observable
final class DisplaySettings {
    var markerLabel: MarkerLabel {
        didSet { defaults.set(markerLabel.rawValue, forKey: "display.markerLabel") }
    }
    var hideUnrelatedNotes: Bool {
        didSet { defaults.set(hideUnrelatedNotes, forKey: "display.hideUnrelatedNotes") }
    }
    /// Colour every note in the collection, not just those in the selected position.
    var highlightAllPositions: Bool {
        didSet { defaults.set(highlightAllPositions, forKey: "display.highlightAllPositions") }
    }
    /// Hide everything outside the selected position.
    var isolatePosition: Bool {
        didSet { defaults.set(isolatePosition, forKey: "display.isolatePosition") }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        markerLabel = defaults.string(forKey: "display.markerLabel").flatMap(MarkerLabel.init) ?? .interval
        hideUnrelatedNotes = defaults.bool(forKey: "display.hideUnrelatedNotes")
        highlightAllPositions = defaults.bool(forKey: "display.highlightAllPositions")
        isolatePosition = defaults.bool(forKey: "display.isolatePosition")
    }
}
