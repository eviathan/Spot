//
//  AppState.swift
//  Spot
//
//  Created by Brian Williams on 16/04/2024.
//

import Foundation

class AppState: ObservableObject {
    @Published var test: String  = "Wooter"
    @Published var instrument: InstrumentType = .guitar
    @Published var selectedNote: Note = .G
}
