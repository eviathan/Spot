//
//  LibraryDetailView.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import SwiftUI

struct LibraryDetailView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedInversion = "Ionian"
    
    let inversions = ["Ionian", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Aeolian", "Locrian"]
    
    var body: some View {
        VStack {
            Text(appState.getSelectedName())
                .font(.title)
                .frame(maxHeight: .infinity)
            
            VStack {
//                Text("Library Detail View")
                
//                Picker("Inversion", selection: $selectedInversion) {
//                    ForEach(inversions, id: \.self) {
//                            Text($0)
//                        }
//                }
//                .pickerStyle(DefaultPickerStyle())
//                
//                Dropdown()
//                
//                Text("TODO: Edit button link to edit screen")
            }
            .padding(24)
            .frame(maxHeight: .infinity)
            
            IntervalBannerView(intervals: appState.getSelectedIntervals(), theme: appState.theme)
        }
    }
}
