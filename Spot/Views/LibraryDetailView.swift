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
            Text(appState.getSelectedName())
                .frame(maxHeight: .infinity)
            
            //TODO: Wildly innefficient and verbose - Fix this mess!
            HStack(spacing: 4) {
                if(appState.getSelectedIntervals().contains(.I)) {
                    drawMarker("R", markerColor: appState.theme.markerColours[0])
                }
                if(appState.getSelectedIntervals().contains(.bII)) {
                    drawMarker("m2", markerColor: appState.theme.markerColours[1])
                }
                
                if(appState.getSelectedIntervals().contains(.II)) {
                    drawMarker("M2", markerColor: appState.theme.markerColours[1])
                }
                
                if(appState.getSelectedIntervals().contains(.bIII)) {
                    drawMarker("m3", markerColor: appState.theme.markerColours[2])
                }
                
                if(appState.getSelectedIntervals().contains(.III)) {
                    drawMarker("M3", markerColor: appState.theme.markerColours[2])
                }
                
                if(appState.getSelectedIntervals().contains(.IV)) {
                    drawMarker("P4", markerColor: appState.theme.markerColours[3])
                }
                
                if(appState.getSelectedIntervals().contains(.bV)) {
                    drawMarker("TT", markerColor: appState.theme.markerColours[3])
                }
                
                if(appState.getSelectedIntervals().contains(.V)) {
                    drawMarker("P5", markerColor: appState.theme.markerColours[4])
                }
                
                if(appState.getSelectedIntervals().contains(.bVI)) {
                    drawMarker("m6", markerColor: appState.theme.markerColours[5])
                }
                
                if(appState.getSelectedIntervals().contains(.VI)) {
                    drawMarker("M6", markerColor: appState.theme.markerColours[5])
                }
                
                if(appState.getSelectedIntervals().contains(.bVII)) {
                    drawMarker("m7", markerColor: appState.theme.markerColours[6])
                }
                
                if(appState.getSelectedIntervals().contains(.VII)) {
                    drawMarker("M7", markerColor: appState.theme.markerColours[6])
                }
            }
            .padding([.top], 4)
            .padding([.bottom], 12)
            .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
            .background(Color(hue: 1.00, saturation: 0.00, brightness: 0.93, opacity: 1.00))
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
