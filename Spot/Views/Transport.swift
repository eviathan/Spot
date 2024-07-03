//
//  Transport.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct Transport: View {
    
    @State private var isPlaying: Bool = false;
    @State private var isRecording: Bool = false;
    @State private var isLooping: Bool = false;
    @State private var isMetronomeOn: Bool = false;
    @State private var bpm = 120
    
    func onClickTransport() -> Void {
        
    }
    
    func onClickTransportPlay() -> Void {
        isPlaying = !isPlaying;
    }
    
    func onClickTransportRecord() -> Void {
        isRecording = !isRecording;
    }
    
    func onClickTransportLoop() -> Void {
        isLooping = !isLooping;
    }
    
    func onClickTransportMetronome() -> Void {
        isMetronomeOn = !isMetronomeOn;
    }
    
    var body: some View {
        Button(action: onClickTransportMetronome)
        {
            Image(systemName: "metronome")
                .imageScale(.large)
                .foregroundColor(isMetronomeOn ? .white : Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00))
            
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransportRecord)
        {
            Image(systemName: isRecording ? "smallcircle.fill.circle.fill" : "circle.fill")
                .imageScale(.large)
                .foregroundColor(isRecording ? Color(red:0.83, green:0.38, blue:0.42) : .white)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransport)
        {
            Image(systemName: "backward.end.fill")
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransportPlay)
        {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .imageScale(.large)
//                .foregroundColor(isRecording ? Color(red:0.83, green:0.38, blue:0.42) : isPlaying ? Color(red:0.69, green:0.85, blue:0.60) : .white)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransport)
        {
            Image(systemName: "forward.end.fill")
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransportLoop)
        {
            Image(systemName: "recordingtape")
                .imageScale(.large)
                .foregroundColor(isLooping ? .white : Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00))
            
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Stepper("\(bpm) BPM", value: $bpm)
    }
}

#Preview {
    Transport()
}
