//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//
import SwiftUI

// TODO: This is innefficient we can reduce the iterations down to a single pass based on the fretboard
// calculated with getNotesForTuning(tuning: [.E, .A, .D, .G, .B, .E], frets: 24) and do it in O(n) instead
struct FretboardView: View {
    @EnvironmentObject var appState: AppState
    
    let numberOfFrets: Int = 22
    let numberOfStrings: Int = 6
    let fretboardColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    let stringColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.28, opacity: 1.00)
    
    let markerColorA = Color(hue: 0.04, saturation: 0.48, brightness: 0.95, opacity: 1.00)
    let markerColorB = Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00)
    let markerColorC = Color(hue: 0.62, saturation: 0.58, brightness: 0.86, opacity: 1.00)
    
    let markerSize: CGFloat = 30.0
    
//    let fretboard = NoteService.getNotesForTuning(tuning: [.E, .A, .D, .G, .B, .E].reversed(), frets: 22)
    
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
                for fret in 1...numberOfFrets {
                    let lineWidth: CGFloat = (fret == 12) ? 3 : 1 // Make the 12th fret line thicker
                    let x = CGFloat(fret) * fretSpacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    path.closeSubpath()
                                        
                    // Draw the path for each fret to allow different line widths
                    if fret == 12 {
                        // Optional: Add some more styling to the 12th fret, like a different color
                        let highlightColor = Color.red // Example highlight color
                        let _ = path.stroke(highlightColor, lineWidth: lineWidth)
                    } else {
                        let _ = path.stroke(stringColor, lineWidth: lineWidth)
                    }
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
            
            // Draw fret numbers
            ForEach(1...numberOfFrets, id: \.self) { fret in
                let x = CGFloat(fret) * fretSpacing - fretSpacing / 2
                // Align the numbers with the bottom of the fret lines
                let y = height - (stringSpacing / 4) // Adjust this value as needed to move the number up or down

                Text("\(fret)")
                    .font(.caption)
                    .foregroundColor(fretboardColor)
                    .frame(width: fretSpacing, height: stringSpacing / 2, alignment: .top)
                    .position(x: x, y: y)
            }
            
            // Draw markers
            ForEach(0..<appState.fretboardViewModel.notes.count, id: \.self) { noteIndex in
                let note = appState.fretboardViewModel.notes[noteIndex]
                
                ForEach(0..<note.count, id: \.self) { fretIndex in
                    let fret = note[fretIndex]
                    let noteInChord = appState.fretboardViewModel.chord.intervals.contains(fret.getInterval(rootNote: .A))
//                    fretIndex == 0 ? "O" : "X"
                    
                    let x = CGFloat(fretIndex) * fretSpacing - (fretIndex == 0 ? 0 : fretSpacing / 2)
                    let y = CGFloat(noteIndex + 1) * stringSpacing
                    let markerColor = fretIndex == 0
                        ? markerColorB
                        : fret.type == .A
                            ? markerColorC
                            : markerColorA

                    Circle()
                        .fill(markerColor)
                        .frame(width: markerSize, height: markerSize)
                        .overlay(
                            Text(fret.getLabel()) // "O" for open string, "•" for fretted
                                .font(.caption)
                                .foregroundColor(fretboardColor)
                        )
                        .position(x: x, y: y)
                        .opacity(noteInChord ? 1 : 0.5)
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
