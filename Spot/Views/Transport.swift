//
//  Transport.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI

struct Transport: View {
    
    @Environment(TransportState.self) private var transport
    @Environment(PlaybackController.self) private var playback
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui
    
    /// On the Sequence tab, play the open sequence.
    private var playsSequence: Bool {
        ui.tab == .Sequence && session.isOpen
    }
   
    func onClickTransport() -> Void {
        
    }
    
    /// Back to the start (with the count-in again) if playing.
    func onClickTransportRestart() -> Void {
        if transport.isPlaying {
            let wasSequence = session.isPlaying
            playback.stop()
            wasSequence ? session.togglePlay() : playback.play()
        }
    }
    
    func onClickTransportPlay() -> Void {
        if playsSequence && !transport.isPlaying {
            session.togglePlay()
        } else {
            playback.togglePlay()
        }
    }
    
    func onClickTransportRecord() -> Void {
        transport.isRecording.toggle()
    }
    
    func onClickTransportLoop() -> Void {
        transport.isLooping.toggle()
    }
    
    func onClickTransportMetronome() -> Void {
        transport.isMetronomeOn.toggle()
    }
    
    var body: some View {
        Button(action: onClickTransportMetronome)
        {
            Image(systemName: "metronome")
                .imageScale(.large)
                .foregroundColor(transport.isMetronomeOn ? .white : Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00))
            
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransportRecord)
        {
            Image(systemName: transport.isRecording ? "smallcircle.fill.circle.fill" : "circle.fill")
                .imageScale(.large)
                .foregroundColor(transport.isRecording ? Color(red:0.83, green:0.38, blue:0.42) : .white)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransportRestart)
        {
            Image(systemName: "backward.end.fill")
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransportPlay)
        {
            Image(systemName: transport.isPlaying ? "stop.fill" : "play.fill")
                .imageScale(.large)
//                .foregroundColor(transport.isRecording ? Color(red:0.83, green:0.38, blue:0.42) : transport.isPlaying ? Color(red:0.69, green:0.85, blue:0.60) : .white)
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
                .foregroundColor(transport.isLooping ? .white : Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00))
            
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        PositionDisplay()
    }
}

/// Bar and beat, e.g. "3.2". Shows the count-in as bar 0.
private struct PositionDisplay: View {
    @Environment(TransportState.self) private var transport
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !transport.isPlaying)) { context in
            let position = transport.clock.barAndBeat(transport.position())
            Text(transport.isPlaying ? "\(position.bar).\(position.beat)" : "1.1")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(transport.isPlaying && position.bar < 1 ? .orange : .white)
                .frame(width: 56)
        }
    }
}

#Preview {
    let transport = TransportState()
    return Transport()
        .environment(transport)
        .environment(PlaybackController(transport: transport, settings: AudioSettings()))
}
