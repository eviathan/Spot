//
//  LibraryDetailView.swift
//  Spot
//
//  Created by Brian Williams on 03/07/2024.
//

import SwiftUI

struct LibraryDetailView: View {
    
    @EnvironmentObject var appState: AppState
    
    @State var markerSize: CGFloat = 30;
    
    var body: some View {
        VStack {
            HStack(spacing: 4) {
                drawMarker("R", markerColor: appState.theme.markerColours[0])
                drawMarker("m2", markerColor: appState.theme.markerColours[1])
                drawMarker("M2", markerColor: appState.theme.markerColours[1])
                drawMarker("m3", markerColor: appState.theme.markerColours[2])
                drawMarker("M3", markerColor: appState.theme.markerColours[2])
                drawMarker("P4", markerColor: appState.theme.markerColours[3])
                drawMarker("A4", markerColor: appState.theme.markerColours[3])
                drawMarker("P5", markerColor: appState.theme.markerColours[4])
                drawMarker("m6", markerColor: appState.theme.markerColours[5])
                drawMarker("M6", markerColor: appState.theme.markerColours[5])
                drawMarker("m7", markerColor: appState.theme.markerColours[6])
                drawMarker("M7", markerColor: appState.theme.markerColours[6])
            }
            .padding([.top, .bottom], 12)
            .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
            .background(Color(hue: 1.00, saturation: 0.00, brightness: 0.93, opacity: 1.00))
            
            Text("Library Detail View")
                .frame(maxHeight: .infinity)
        }
    }
    
    func drawMarker(_ label: String, markerColor: Color) -> some View {
        return ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: markerSize, height: markerSize)
            Circle()
                .stroke(markerColor, lineWidth: 5)
                .frame(width: markerSize - 4, height: markerSize - 4)
            Text(label)
                .font(.caption)
                .foregroundColor(.white)
        }
    }

}
