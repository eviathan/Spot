//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct FretboardView: View {
    let numberOfFrets: Int = 20
    let numberOfStrings: Int = 7
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stringSpacing = height / CGFloat(numberOfStrings + 1)
            let fretSpacing = width / CGFloat(numberOfFrets + 1)
            
            Path { path in
                // Draw fretboard
                path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                
                // Draw frets
                for fret in 1...numberOfFrets {
                    let x = CGFloat(fret) * fretSpacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                
                // Draw strings
                for string in 1...numberOfStrings {
                    let y = CGFloat(string) * stringSpacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.black, lineWidth: 2)
            
            // Draw markers
            ForEach(1...numberOfStrings, id: \.self) { string in
                ForEach(1...numberOfFrets, id: \.self) { fret in
                    let x = CGFloat(fret) * fretSpacing - fretSpacing / 2
                    let y = CGFloat(string) * stringSpacing
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: stringSpacing / 2, height: stringSpacing / 2)
                        .overlay(
                            Text("Note")
                                .font(.caption)
                        )
                        .position(x: x, y: y)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 350)
        .padding()
        .background(Color.yellow)
    }
}

struct FretboardView_Previews: PreviewProvider {
    static var previews: some View {
        FretboardView()
    }
}
