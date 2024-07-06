//
//  Footer.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct Footer: View {
    @EnvironmentObject var appState: AppState
    @State private var bpm = 120
    @State private var previousBPMChangeValue:CGFloat =  0
    
    let backgroundColor = Color(hue: 0.62, saturation: 0.34, brightness: 0.20, opacity: 1.00)
    
    func incrementSelectedNote(_ value: Int) {
        appState.selectedNote = appState.selectedNote.increment(value)
    }
    
    func incrementBPM(_ value: Int) {
        appState.bpm += value
    }
    
    var body: some View {
        HStack {
            Spacer()
            ModeSwitcher()
            Spacer()
            Transport()
            Spacer()
            HStack {
                RangePicker(data: Note.allCases,
                            onDecrement: {incrementSelectedNote(-1)},
                            onIncrement: {incrementSelectedNote(1)}) { value in
                    
                    Image(systemName: "tuningfork")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                    
                    Text(appState.selectedNote.longDescription)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(minWidth: 50)
                }
                
                RangePicker(data: 1..<10,
                            onDecrement: {incrementBPM(-1)},
                            onIncrement: {incrementBPM(1)}) { value in
                    
                    HStack {
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        
                        Text("\(appState.bpm)")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(minWidth: 50)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if(value.translation.width < previousBPMChangeValue) {
                                    incrementBPM(-1)
                                } else if (value.translation.width > previousBPMChangeValue) {
                                    incrementBPM(1)
                                }
                                
                                previousBPMChangeValue = value.translation.width
                            })
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.black)
        .foregroundColor(.white)
    }
}
