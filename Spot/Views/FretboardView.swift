//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//
import SwiftUI

// TODO: This is innefficient we can reduce the iterations down to a single pass based on the fretboard
struct FretboardView: View {
    @EnvironmentObject var appState: AppState
    
    let numberOfFrets: Int = 24
    let numberOfStrings: Int = 6
    
    let fretboardColor = Color(hue: 0.61, saturation: 0.42, brightness: 0.31, opacity: 1.00)
    let stringColor = Color(hue: 0.63, saturation: 0.13, brightness: 0.28, opacity: 1.00)
    let markerColorA = Color(hue: 0.04, saturation: 0.48, brightness: 0.95, opacity: 1.00)
    let markerColorB = Color(hue: 0.98, saturation: 0.62, brightness: 0.89, opacity: 1.00)
    let markerColorC = Color(hue: 0.62, saturation: 0.58, brightness: 0.86, opacity: 1.00)
    
    let markerSize: CGFloat = 30.0
    
    var body: some View {
        let viewModel: FretboardViewModel = FretboardViewModel(appState: appState)
        
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let fretSpacing = width / CGFloat(numberOfFrets + 1)
            let stringSpacing = height / CGFloat(numberOfStrings + 1)
            
            ZStack {
                drawNut(width: width, height: height)
                drawFrets(width: width, height: height, fretSpacing: fretSpacing)
                drawStrings(width: width, height: height, stringSpacing: stringSpacing)
                drawFretNumbers(width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                drawMarkers(viewModel: viewModel, width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 300)
        .padding()
    }
    
    func drawNut(width: CGFloat, height: CGFloat) -> some View {
        let nutWidth: CGFloat = 6
        let nutX = nutWidth / 2
        
        return Path { path in
            path.move(to: CGPoint(x: nutX, y: 0))
            path.addLine(to: CGPoint(x: nutX, y: height))
        }
        .stroke(stringColor, lineWidth: 6)
    }
    
    func drawFrets(width: CGFloat, height: CGFloat, fretSpacing: CGFloat) -> some View {
        ZStack {
            // Default frets
            ForEach(1...numberOfFrets, id: \.self) { fret in
                Path { path in
                    let x = CGFloat(fret) * fretSpacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                .stroke(fret == 12 ? stringColor : stringColor,
                        lineWidth: fret == 12 ? 3 : 1
                )
            }
        }
    }
    
    func drawStrings(width: CGFloat, height: CGFloat, stringSpacing: CGFloat) -> some View {
        return Path { path in
            for string in 1...numberOfStrings {
                let y = CGFloat(string) * stringSpacing
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
        .stroke(stringColor, lineWidth: 1)
    }
    
    func drawFretNumbers(width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
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
    }
    
    func drawMarkers(viewModel: FretboardViewModel, width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        ForEach(0..<viewModel.notes.count, id: \.self) { noteIndex in
            let note = viewModel.notes[noteIndex]
            
            ForEach(0..<note.count, id: \.self) { fretIndex in
                let fret = note[fretIndex]
                let noteInChord = viewModel.chord.intervals.contains(
                    fret.getInterval(rootNote: appState.selectedNote)
                )
//                    fretIndex == 0 ? "O" : "X"
                
                let x = CGFloat(fretIndex) * fretSpacing - (fretIndex == 0 ? 0 : fretSpacing / 2)
                let y = CGFloat(noteIndex + 1) * stringSpacing
                let markerColor = !noteInChord
                    ? Color.white
                    : fretIndex == 0
                        ? markerColorB
                        : fret.type == appState.selectedNote
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
//                        .opacity(noteInChord ? 1 : 0.5)
            }
        }
    }
}

struct FretboardView_Previews: PreviewProvider {
    static var previews: some View {
        FretboardView()
    }
}
