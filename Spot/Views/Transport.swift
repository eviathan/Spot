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
    
    func onClickTransport() -> Void {
        
    }
    
    func onClickTransportRestart() -> Void {
        TransportActions.toStart(ui: ui, session: session, playback: playback)
    }
    
    func onClickTransportPlay() -> Void {
        TransportActions.playPause(ui: ui, session: session, playback: playback)
    }
    
    func onClickTransportStop() -> Void {
        TransportActions.stop(ui: ui, session: session, playback: playback)
    }
    
    func onClickTransportRecord() -> Void {
        TransportActions.record(ui: ui, session: session)
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
            Image(systemName: session.isRecording ? "smallcircle.fill.circle.fill" : "circle.fill")
                .imageScale(.large)
                .foregroundColor(session.isRecording ? Color(red:0.83, green:0.38, blue:0.42) : .white)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help(ui.tab == .Sequence && session.isOpen ? "Record a take over the sequence" : "Open a sequence to record over it")
        .disabled(!(ui.tab == .Sequence && session.isOpen))
        
        Button(action: onClickTransportRestart)
        {
            Image(systemName: "backward.end.fill")
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help("Back to bar 1")
        
        Button(action: onClickTransportPlay)
        {
            Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                .imageScale(.large)
//                .foregroundColor(transport.isRecording ? Color(red:0.83, green:0.38, blue:0.42) : transport.isPlaying ? Color(red:0.69, green:0.85, blue:0.60) : .white)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help("Play / pause (space)")
        
        Button(action: onClickTransportStop)
        {
            Image(systemName: "stop.fill")
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help("Stop and go back to the selection")
        
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

/// Play/pause, stop and back-to-start, shared by the footer, the Playback menu and the space bar.
/// On the Sequence tab they control the open sequence; elsewhere, the metronome transport.
enum TransportActions {
    static func playPause(ui: UIState, session: SequenceSession, playback: PlaybackController) {
        if session.isPlaying || (ui.tab == .Sequence && session.isOpen && !playback.transport.isPlaying) {
            session.togglePlay()
        } else {
            playback.togglePlay()
        }
    }
    
    static func stop(ui: UIState, session: SequenceSession, playback: PlaybackController) {
        if session.isOpen {
            session.stopPlayback()
        }
        if playback.transport.isPlaying {
            playback.stop()
        }
    }
    
    /// Starts or stops recording a take. A sequence that hasn't been saved is saved first (takes live in its file).
    static func record(ui: UIState, session: SequenceSession) {
        guard ui.tab == .Sequence, session.isOpen else { return }
        if session.isRecording {
            session.stopRecording()
        } else if session.fileURL == nil {
            ui.sequenceActionAfterSave = .startRecording
            ui.isSavingSequenceAs = true
        } else {
            do {
                try session.startRecording()
            } catch {
                ui.errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            }
        }
    }
    
    static func toStart(ui: UIState, session: SequenceSession, playback: PlaybackController) {
        if ui.tab == .Sequence && session.isOpen {
            session.returnToStart()
        } else if playback.transport.isPlaying {
            playback.stop()
            playback.play()
        }
    }
}

/// The space bar toggles play/pause anywhere in the window, except while typing in a text field.
enum SpaceBarMonitor {
    private static var monitor: Any?
    
    static func install(_ action: @escaping () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isTyping = NSApp.keyWindow?.firstResponder is NSText
            guard event.keyCode == 49, modifiers.isEmpty, !isTyping, !event.isARepeat else {
                return event
            }
            action()
            return nil
        }
    }
}
