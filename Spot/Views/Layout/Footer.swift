//
//  Footer.swift
//  Spot
//
//  Created by Brian Williams on 15/04/2024.
//

import SwiftUI

struct Footer: View {
    @Environment(SelectionState.self) private var selection
    @Environment(TransportState.self) private var transport
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui
    @State private var previousBPMChangeValue:CGFloat =  0
    
    let backgroundColor = Color(hue: 0.62, saturation: 0.34, brightness: 0.20, opacity: 1.00)
    
    func incrementSelectedNote(_ value: Int) {
        selection.transposeRoot(by: value)
    }
    
    /// On the Sequence tab the tempo belongs to the sequence.
    private var editsSequenceTempo: Bool {
        ui.tab == .Sequence && session.isOpen
    }
    
    private var bpm: Int {
        editsSequenceTempo ? Int(session.sequence?.tempo.rounded() ?? 0) : transport.bpm
    }
    
    func incrementBPM(_ value: Int) {
        if editsSequenceTempo, let tempo = session.sequence?.tempo {
            session.sequence?.tempo = min(max(tempo.rounded() + Double(value), 20), 300)
            if !session.isPlaying {
                transport.setBPM(bpm)
            }
        } else {
            transport.incrementBPM(value)
        }
    }
    
    var body: some View {
        HStack {
            Spacer()
            ModeSwitcher()
            Spacer()
            Transport()
            Spacer()
            HStack {
                RangePicker(data: 0..<12,
                            onDecrement: {incrementSelectedNote(-1)},
                            onIncrement: {incrementSelectedNote(1)}) { value in
                    
                    Image(systemName: "tuningfork")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                    
                    Text(selection.spelledRoot.description)
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
                        
                        Text("\(bpm)")
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
