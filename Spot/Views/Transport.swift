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
        TransportActions.toggleLoop(ui: ui, session: session, tab: tabSession)
    }
    
    /// The transport is the sequence's (from any page, unless the Tab tab is showing a tab of its own).
    private var editsSequence: Bool {
        TransportActions.target(ui: ui, session: session, tab: tabSession) == .sequence
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
                .foregroundColor(transport.isMetronomeOn ? SpotStyle.text : SpotStyle.dimmed)
            
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        
        // Button(action: onClickTransportRecord)
        // {
        //     Image(systemName: session.isRecording ? "smallcircle.fill.circle.fill" : "circle.fill")
        //         .imageScale(.large)
        //         .foregroundColor(session.isRecording ? Color(red:0.83, green:0.38, blue:0.42) : .white)
        // }
        // .buttonStyle(PlainButtonStyle())
        // .frame(width: 30, height: 30)
        // .help(ui.tab == .Sequence && session.isOpen ? "Record a take over the sequence" : "Open a sequence to record over it")
        // .disabled(!(ui.tab == .Sequence && session.isOpen))
        
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
                .foregroundColor(transport.isPlaying ? SpotStyle.accent : SpotStyle.text)
//                .foregroundColor(transport.isRecording ? Color(red:0.83, green:0.38, blue:0.42) : transport.isPlaying ? Color(red:0.69, green:0.85, blue:0.60) : .white)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 30, height: 30)
        .help(TransportActions.target(ui: ui, session: session, tab: tabSession) == .tab
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
                .foregroundColor(isLooping ? ThemeStore.shared.current.loop : SpotStyle.dimmed)
            
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
                .foregroundColor(transport.isPlaying && position.bar < 1 ? SpotStyle.warning : SpotStyle.text)
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
/// They work from every page: on whatever's playing, or the open sequence (or, on the Tab tab, its tab).
enum TransportActions {
    enum Target {
        /// The Tab tab's own tab (one that isn't a sequence's: a sequence's tab plays with the sequence).
        case tab
        case sequence
        /// Nothing open: just the clock and metronome.
        case metronome
    }

    /// What the transport plays: what's playing; on the Tab tab, its tab; anywhere else, the open sequence (or,
    /// with none, a tab that's open).
    static func target(ui: UIState, session: SequenceSession, tab: TabSession) -> Target {
        if tab.isPlaying && tab.linkedSequence == nil { return .tab }
        if session.isPlaying { return .sequence }
        if ui.tab == .Tab && tab.isOpen { return tab.linkedSequence == nil ? .tab : .sequence }
        if session.isOpen { return .sequence }
        if tab.isOpen { return tab.linkedSequence == nil ? .tab : .sequence }
        return .metronome
    }

    /// Space: play from the start marker (1.1.1), or stop.
    static func playPause(ui: UIState, session: SequenceSession, tab: TabSession, playback: PlaybackController) {
        switch target(ui: ui, session: session, tab: tab) {
        case .tab: tab.togglePlay()
        case .sequence: session.togglePlay()
        case .metronome: playback.togglePlay()
        }
    }

    /// ⌥Space: play from the playhead (a selected range on its own, stopping at its end); while playing,
    /// jump back to the playhead. On the Tab tab, from the cursor.
    static func playSelection(ui: UIState, session: SequenceSession, tab: TabSession, playback: PlaybackController) {
        switch target(ui: ui, session: session, tab: tab) {
        case .tab:
            tab.play(fromCursor: true)
        case .sequence:
            // The sequence's tab, on the Tab tab: from its cursor
            if ui.tab == .Tab && tab.linkedSequence != nil {
                tab.play(fromCursor: true)
            } else {
                session.playSelection()
            }
        case .metronome:
            playback.togglePlay()
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
    /// On the Tab tab with the sequence's tab, the selected beats are looped (or looping turned on or off).
    static func toggleLoop(ui: UIState, session: SequenceSession, tab: TabSession) {
        guard target(ui: ui, session: session, tab: tab) == .sequence else { return }
        if ui.tab == .Tab, tab.linkedSequence != nil {
            session.loop(tab.selectionBeats)
        } else {
            session.toggleLoop()
        }
    }
    
    static func toStart(ui: UIState, session: SequenceSession, tab: TabSession, playback: PlaybackController) {
        let target = target(ui: ui, session: session, tab: tab)
        if target == .tab || (target == .sequence && ui.tab == .Tab && tab.linkedSequence != nil) {
            tab.returnToStart()
        } else if target == .sequence {
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

/// Delete (or forward delete) on the Sequence tab clears the selection, except while typing in a text field.
enum DeleteKeyMonitor {
    private static var monitor: Any?

    static func install(_ action: @escaping () -> Bool) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isTyping = NSApp.keyWindow?.firstResponder is NSText
            guard event.keyCode == 51 || event.keyCode == 117, modifiers.isEmpty, !isTyping,
                  NSApp.keyWindow?.attachedSheet == nil else {
                return event
            }
            return action() ? nil : event
        }
    }
}
