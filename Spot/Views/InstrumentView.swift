//
//  InstrumentView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct InstrumentView: View {
    @Environment(UIState.self) private var ui
    
    var body: some View {
        if ![.Sequence, .Settings].contains(ui.tab) {
            FretboardView()
        }
    }
}

struct InstrumentView_Previews: PreviewProvider {
    static var previews: some View {
        InstrumentView()
    }
}
