//
//  DisplaySettings.swift
//  Spot
//

import Foundation
import Observation

/// How the instrument is drawn. Saved between launches.
@Observable
final class DisplaySettings {
    var showIntervalLabels: Bool {
        didSet { defaults.set(showIntervalLabels, forKey: "display.showIntervalLabels") }
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
        showIntervalLabels = defaults.object(forKey: "display.showIntervalLabels") as? Bool ?? true
        hideUnrelatedNotes = defaults.bool(forKey: "display.hideUnrelatedNotes")
        highlightAllPositions = defaults.bool(forKey: "display.highlightAllPositions")
        isolatePosition = defaults.bool(forKey: "display.isolatePosition")
    }
}
