//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//
import SwiftUI

struct FretboardView: View {
    let numberOfFrets: Int = 24
    let numberOfStrings: Int = 6
    let fretboardColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    let stringColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.28, opacity: 1.00)
    
    let markerColorA = Color(hue: 0.04, saturation: 0.48, brightness: 0.95, opacity: 1.00)
    let markerColorB = Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00)
    
    let markerSize: CGFloat = 30.0
    
    let fretboard = getNotesForTuning(tuning: [.E, .A, .D, .G, .B, .E], frets: 24)
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stringSpacing = height / CGFloat(numberOfStrings + 1)
            let fretSpacing = width / CGFloat(numberOfFrets + 1)
            
            Path { path in
                // Draw the nut of the guitar
                let nutWidth: CGFloat = 6
                let nutX = nutWidth / 2
                path.move(to: CGPoint(x: nutX, y: 0))
                path.addLine(to: CGPoint(x: nutX, y: height))
            }
            .stroke(stringColor, lineWidth: 6)
            
            Path { path in
                // Draw frets
                for fret in 1..<numberOfFrets {
                    let x = CGFloat(fret) * fretSpacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
            }
            .stroke(stringColor, lineWidth: 1)
            
            Path { path in
                // Draw strings
                for string in 1...numberOfStrings {
                    let y = CGFloat(string) * stringSpacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(stringColor, lineWidth: 1)
            
            // Draw markers
            ForEach(0..<numberOfStrings, id: \.self) { string in
                ForEach(0..<numberOfFrets, id: \.self) { fret in
                    let x = CGFloat(fret) * fretSpacing - (fret == 0 ? 0 : fretSpacing / 2)
                    let y = CGFloat(string + 1) * stringSpacing

                    Circle()
                        .fill(fret == 0 ? markerColorB : markerColorA)
                        .frame(width: markerSize, height: markerSize)
                        .overlay(
                            Text(fret == 0 ? "O" : "X") // "O" for open string, "•" for fretted
                                .font(.caption)
                                .foregroundColor(fretboardColor)
                        )
                        .position(x: x, y: y)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 300)
        .padding()
    }
}

struct FretboardView_Previews: PreviewProvider {
    static var previews: some View {
        FretboardView()
    }
}
