//
//  UIState.swift
//  Spot
//

import Foundation
import Observation

/// Window layout: the current tab and which sidebars are open. Sidebars are saved between launches.
@Observable
final class UIState {
    var tab: TabViewType = .Library
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
