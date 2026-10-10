//
//  Transport.swift
//  Spot
//
//  Created by Brian Williams on 02/07/2024.
//

import SwiftUI
import SpotCore

struct Transport: View {
    
    @Environment(TransportState.self) private var transport
    @Environment(PlaybackController.self) private var playback
    @Environment(SequenceSession.self) private var session
    @Environment(TabSession.self) private var tabSession
    @Environment(UIState.self) private var ui
    
    func onClickTransport() -> Void {
        
    }
    
    func onClickTransportRestart() -> Void {
        TransportActions.toStart(ui: ui, session: session, tab: tabSession, playback: playback)
    }
    
    func onClickTransportPlay() -> Void {
        TransportActions.playPause(ui: ui, session: session, tab: tabSession, playback: playback)
    }
    
    func onClickTransportStop() -> Void {
        TransportActions.stop(ui: ui, session: session, tab: tabSession, playback: playback)
    }
    
    func onClickTransportRecord() -> Void {
        TransportActions.record(ui: ui, session: session)
    }
    
    /// Loops the selection, or stops looping.
    func onClickTransportLoop() -> Void {
        TransportActions.toggleLoop(session: session)
    }
    
    private var editsSequence: Bool {
        ui.tab == .Sequence && session.isOpen
    }
    
    private var isLooping: Bool {
        editsSequence && session.sequence?.loop != nil
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
            Image(systemName: "play.fill")
                .imageScale(.large)
                .foregroundColor(transport.isPlaying ? Color(red: 0.55, green: 0.85, blue: 0.45) : .white)
//                .foregroundColor(transport.isRecording ? Color(red:0.83, green:0.38, blue:0.42) : transport.isPlaying ? Color(red:0.69, green:0.85, blue:0.60) : .white)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help(ui.tab == .Tab
              ? "Play the tab from the start, or stop (space). ⌥Space plays from the cursor."
              : "Play from 1.1.1, or stop (space). ⌥Space plays from the playhead (or just the selected range).")
        
        Button(action: onClickTransportStop)
        {
            Image(systemName: "stop.fill")
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help("Stop")
        
        Button(action: onClickTransport)
        {
            Image(systemName: "forward.end.fill")
                .imageScale(.large)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        Button(action: onClickTransportLoop)
        {
            Image(systemName: "repeat")
                .imageScale(.large)
                .foregroundColor(isLooping ? .yellow : Color(hue: 0.62, saturation: 0.38, brightness: 0.38, opacity: 1.00))
            
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .disabled(!editsSequence)
        .help(isLooping ? "Stop looping (⌘L), or loop a different selected range" : "Loop the selected range, or bring back the last loop (⌘L)")
        
        PositionDisplay()
    }
}

/// Bar and beat, e.g. "3.2". Shows the count-in as bar 0.
private struct PositionDisplay: View {
    @Environment(TransportState.self) private var transport
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !transport.isPlaying)) { context in
            let position = transport.clock.barAndBeat(transport.position() - transport.barOrigin)
            let label = transport.positionLabel.map { $0(transport.position()) } ?? "\(position.bar).\(position.beat)"
            Text(transport.isPlaying ? label : "1.1")
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
    /// Space: play from the start marker (1.1.1), or stop.
    static func playPause(ui: UIState, session: SequenceSession, tab: TabSession, playback: PlaybackController) {
        if tab.isPlaying || (ui.tab == .Tab && tab.isOpen && !playback.transport.isPlaying) {
            tab.togglePlay()
        } else if session.isPlaying || (ui.tab == .Sequence && session.isOpen && !playback.transport.isPlaying) {
            session.togglePlay()
        } else {
            playback.togglePlay()
        }
    }

    /// ⌥Space: play from the playhead (a selected range on its own, stopping at its end); while playing,
    /// jump back to the playhead.
    static func playSelection(ui: UIState, session: SequenceSession, tab: TabSession, playback: PlaybackController) {
        if ui.tab == .Tab && tab.isOpen {
            // From the cursor (while playing, jump back to it)
            tab.play(fromCursor: true)
        } else if session.isPlaying || (ui.tab == .Sequence && session.isOpen && !playback.transport.isPlaying) {
            session.playSelection()
        } else {
            playPause(ui: ui, session: session, tab: tab, playback: playback)
        }
    }
    
    static func stop(ui: UIState, session: SequenceSession, tab: TabSession, playback: PlaybackController) {
        if tab.isPlaying {
            tab.stopPlaying()
        }
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
    
    /// Loops the open sequence's selection, or turns the loop off.
    static func toggleLoop(session: SequenceSession) {
        session.toggleLoop()
    }
    
    static func toStart(ui: UIState, session: SequenceSession, tab: TabSession, playback: PlaybackController) {
        if ui.tab == .Tab && tab.isOpen {
            let wasPlaying = tab.isPlaying
            tab.stopPlaying()
            tab.editor?.cursor = TabEditorState.Cursor()
            if wasPlaying { tab.play(fromCursor: false) }
        } else if ui.tab == .Sequence && session.isOpen {
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
    
    /// `action` is told whether ⌥ was held.
    static func install(_ action: @escaping (_ option: Bool) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isTyping = NSApp.keyWindow?.firstResponder is NSText
            guard event.keyCode == 49, modifiers.isEmpty || modifiers == .option, !isTyping, !event.isARepeat else {
                return event
            }
            action(modifiers == .option)
            return nil
        }
    }
}
