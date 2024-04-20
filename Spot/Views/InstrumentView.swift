//
//  InstrumentView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct InstrumentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        let viewModel  = FretboardViewModel(appState: appState)
        
        return FretboardView(viewModel: viewModel)
    }
}

struct InstrumentView_Previews: PreviewProvider {
    static var previews: some View {
        InstrumentView()
    }
}
