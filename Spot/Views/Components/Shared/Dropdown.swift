//
//  Dropdown.swift
//  Spot
//
//  Created by Brian Williams on 04/07/2024.
//

import SwiftUI

struct Dropdown: View {
    @State private var selectedFingering = "Three Notes Per String"
    
    let fingerings = ["Three Notes Per String", "First Finger", "Second Finger", "Third Finger"]
    
    var body: some View {
        Picker("Fingering", selection: $selectedFingering) {
            ForEach(fingerings, id: \.self) {
                    Text($0)
                }
        }
        .pickerStyle(.menu)
    }
}
