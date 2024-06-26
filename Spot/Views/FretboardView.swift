//
//  FretboardView.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//
import SwiftUI

// TODO: This is innefficient we can reduce the iterations down to a single pass based on the fretboard
struct FretboardView: View {
    @ObservedObject var viewModel: FretboardViewModel
    @State private var mouseOverMarkerIndex: Int? = nil
    
    let markerSize: CGFloat = 0.7 // TODO: Calculate this
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let fretSpacing = width / CGFloat(viewModel.numberOfFrets + 1)
            let stringSpacing = height / CGFloat(viewModel.numberOfStrings + 1)
            
            ZStack {
                drawNut(viewModel: viewModel, width: width, height: height)
                drawFretMarkers(viewModel: viewModel, width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                drawFrets(viewModel: viewModel, width: width, height: height, fretSpacing: fretSpacing)
                drawStrings(viewModel: viewModel, width: width, height: height, stringSpacing: stringSpacing)
                drawFretNumbers(viewModel: viewModel, width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
                drawMarkers(viewModel: viewModel, width: width, height: height, fretSpacing: fretSpacing, stringSpacing: stringSpacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 300)
        .padding()
    }
    
    func drawNut(viewModel: FretboardViewModel, width: CGFloat, height: CGFloat) -> some View {
        let nutWidth: CGFloat = 6
        let nutX = nutWidth / 2
        
        return Path { path in
            path.move(to: CGPoint(x: nutX, y: 0))
            path.addLine(to: CGPoint(x: nutX, y: height))
        }
        .stroke(viewModel.fretColor, lineWidth: 6)
    }
    
    func drawFrets(viewModel: FretboardViewModel, width: CGFloat, height: CGFloat, fretSpacing: CGFloat) -> some View {
        ZStack {
            ForEach(1...viewModel.numberOfFrets, id: \.self) { fret in
                let isTwelthFret = fret % 12 == 11 || fret % 12 == 0
                let fretColour = isTwelthFret ? viewModel.fretColor : viewModel.fretColor
                let fretWidth: CGFloat = isTwelthFret ? 4 : 1
                
                Path { path in
                    let x = CGFloat(fret) * fretSpacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                .stroke(fretColour,style: StrokeStyle(lineWidth: fretWidth))
            }
        }
    }
    
    func drawStrings(viewModel: FretboardViewModel, width: CGFloat, height: CGFloat, stringSpacing: CGFloat) -> some View {
        let exponent: CGFloat = 1.5
        let minStringWidth: CGFloat = 1.0
        let maxStringWidth: CGFloat = 5.0
        
        return ZStack {
            ForEach(1...viewModel.numberOfStrings, id: \.self) { string in
                Path { path in
                    let y = CGFloat(string) * stringSpacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(viewModel.stringColor, 
                        style: StrokeStyle(
                            lineWidth: calculateStringWidth(forString: string,
                                                            totalStrings: viewModel.numberOfStrings,
                                                            minLineWidth: minStringWidth,
                                                            maxLineWidth: maxStringWidth,
                                                            exponent: exponent)
                        )
                )
            }
        }
    }
    
    func drawFretNumbers(viewModel: FretboardViewModel, width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        ForEach(1...viewModel.numberOfFrets, id: \.self) { fret in
            let x = CGFloat(fret) * fretSpacing - fretSpacing / 2
            let y = height - (stringSpacing / 4)

            Text("\(fret)")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.fretboardColor)
                .frame(width: fretSpacing, height: stringSpacing / 2, alignment: .top)
                .position(x: x, y: y)
        }
    }
    
    func drawFretMarkers(viewModel: FretboardViewModel, width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let singleFretMarkers: [Int] = [3, 5, 7, 9, 15, 17, 19, 21] // TODO: Programatically derive this from the fret length
        let doubleFretMarkers: [Int] = [12, 24] // TODO: Programatically derive this from the fret length
        
        return ZStack {
            ForEach(singleFretMarkers, id: \.self) { fret in
                let x = CGFloat(fret) * fretSpacing - fretSpacing / 2
                
                Circle()
                    .fill(viewModel.fretMarkerColor)
                    .frame(width: markerSize * min(fretSpacing, stringSpacing), height: markerSize * min(fretSpacing, stringSpacing))
                    .position(x: x, y: height / 2)
            }

            ForEach(doubleFretMarkers.indices, id: \.self) { index in
                let fret = doubleFretMarkers[index]
                let x = CGFloat(fret) * fretSpacing - fretSpacing / 2
                
                VStack(spacing: stringSpacing) {
                    Circle()
                        .fill(viewModel.fretMarkerColor)
                        .frame(width: markerSize * min(fretSpacing, stringSpacing), height: markerSize * min(fretSpacing, stringSpacing))
                    Circle()
                        .fill(viewModel.fretMarkerColor)
                        .frame(width: markerSize * min(fretSpacing, stringSpacing), height: markerSize * min(fretSpacing, stringSpacing))
                }
                .position(x: x, y: height / 2)
            }
        }
    }

    
    func drawMarkers(viewModel: FretboardViewModel, width: CGFloat, height: CGFloat, fretSpacing: CGFloat, stringSpacing: CGFloat) -> some View {
        let minSpacing = min(fretSpacing, stringSpacing)
        
        return ForEach(0..<viewModel.notes.count, id: \.self) { noteIndex in
            let note = viewModel.notes[noteIndex]
            
            ForEach(0..<note.count, id: \.self) { fretIndex in
                let fret = note[fretIndex]
                // TODO: Move this into the note service
//                let noteInChord = viewModel.chord.intervals.contains(
//                    fret.getInterval(rootNote: appState.selectedNote)
//                )
                
                let noteInCollection = viewModel.scale.intervals.contains(
                    fret.getInterval(rootNote: viewModel.appState.selectedNote)
                )
                
                let isOpenString = fretIndex == 0
                let intervalIndex = viewModel.scale.intervals.firstIndex(of: fret.getInterval(rootNote: viewModel.appState.selectedNote)) ?? 0
                
                let x = CGFloat(fretIndex) * fretSpacing - (isOpenString ? 0 : fretSpacing / 2)
                let y = CGFloat(noteIndex + 1) * stringSpacing
                
                let highlightedNotes = viewModel.getHighlightedNotesforScale(pattern: 4, variation: 0)
                
                let isHighlighted = viewModel.appState.highlightedMode ||
                                    (highlightedNotes.isEmpty ||
                                     highlightedNotes[noteIndex]
                                        .contains(where: { highlightedNote in
                                            highlightedNote % 12 == fretIndex % 12
                                        }))
                
                let colorNoteIndex = viewModel.markerColours[intervalIndex]
                
                let hideUnrelatedNotes = viewModel.appState.hideUnrelatedNotes
                
                let markerColor = !isHighlighted
                    ? isOpenString
                        ? viewModel.openMarkerColor
                        : viewModel.defaultMarkerColor
                    : noteInCollection
                        ? colorNoteIndex
                        : isOpenString
                            ? viewModel.openMarkerColor
                            : viewModel.defaultMarkerColor
                
                let markerSizeModifier = mouseOverMarkerIndex == noteIndex * 100 + fretIndex ? 1.1 : 1.0
                                
                // TODO: Adjust this so that the button wrapps the circle instead
                Circle()
                    .stroke(lineWidth: 6)
                    .fill(markerColor)
                    .background(Circle().fill(noteInCollection ? .black : markerColor))
                    .frame(width: minSpacing * markerSize * markerSizeModifier, height: minSpacing * markerSize * markerSizeModifier)
                    .overlay(
                        Text(fret.getLabel())
                            .font(.caption)
                            .foregroundColor(
                                noteInCollection || isOpenString
                                             ? .white
                                             : viewModel.fretboardColor
                            )
                    )
                    .onTapGesture(perform: { clickedMarker(note: fret.note)})
                    .onHover { isHovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mouseOverMarkerIndex = isHovering ? noteIndex * 100 + fretIndex : nil
                        }
                    }
                    .position(x: x, y: y)
                    .opacity((hideUnrelatedNotes && noteInCollection) || !hideUnrelatedNotes ? 1 : 0)
                    
            }
        }
    }
    
    func clickedMarker(note: Note) {
        viewModel.onNoteClicked(note: note)
    }
    
    private func calculateStringWidth(forString string: Int, totalStrings: Int, minLineWidth: CGFloat, maxLineWidth: CGFloat, exponent: CGFloat) -> CGFloat {
        let normalizedIndex = CGFloat(string - 1) / CGFloat(totalStrings - 1)
        let width = minLineWidth + (maxLineWidth - minLineWidth) * pow(normalizedIndex, exponent)
        return width
    }
}
