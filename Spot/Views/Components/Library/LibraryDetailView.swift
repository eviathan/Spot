//
//  LibraryDetailView.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import SwiftUI

struct LibraryDetailView: View {
    
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack {
            Text(appState.getSelectedName())
                .frame(maxHeight: .infinity)
            
            IntervalBannerView(intervals: appState.getSelectedIntervals(), theme: appState.theme)
        }
    }
}
