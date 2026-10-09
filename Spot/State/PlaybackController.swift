//
//  PlaybackController.swift
//  Spot
//

import Foundation
import Observation
import SpotCore

/// Owns the sound: MIDI out for notes, the internal click for the metronome, and the transport clock.
///
/// Nothing is sent far ahead of time, because some MIDI receivers act on messages as soon as they
/// arrive rather than at their timestamp. A timer sends whatever falls due in the next `lookahead`
/// seconds, stamped with the exact time it should sound.
@Observable
final class PlaybackController {
    let transport: TransportState
    let settings: AudioSettings
    /// Set when MIDI or audio couldn't start, for the Settings tab to show.
    private(set) var problem: String?

    @ObservationIgnored private var midi: MIDIOutput?
    @ObservationIgnored private var clicks: ClickPlayer?
    @ObservationIgnored private var timer: DispatchSourceTimer?
    /// MIDI messages waiting to be sent, kept in time order.
    @ObservationIgnored private var pending: [(time: UInt64, note: Int, velocity: Int?)] = []
    /// Clicks are scheduled up to (but not including) this beat.
    @ObservationIgnored private var clicksScheduledUntil: Double = 0

    private let lookahead = 0.1
    private let startLatency = 0.05

    init(transport: TransportState, settings: AudioSettings) {
        self.transport = transport
        self.settings = settings
        // Create the "Spot" MIDI source straight away so it can be picked in other apps before anything plays
        _ = midiOutput()
    }

    // MARK: - Transport

    func togglePlay() {
        transport.isPlaying ? stop() : play()
    }

    func play() {
        let countIn = Double(settings.countInBars * transport.beatsPerBar)
        transport.start(atBeat: -countIn, hostTime: HostTime.adding(startLatency, to: HostTime.now))
        clicksScheduledUntil = -countIn
        startTimer()
    }

    func stop() {
        transport.stop()
        clicks?.stop()
        midiOutput()?.allNotesOff()
        pending.removeAll()
        stopTimerIfIdle()
    }

    // MARK: - Previewing notes

    /// Plays notes over MIDI, starting now.
    func preview(_ events: [NoteEvent]) {
        guard midiOutput() != nil else { return }
        let start = HostTime.adding(0.02, to: HostTime.now)
        let velocity = settings.previewVelocity

        for event in events {
            pending.append((HostTime.adding(event.time, to: start), event.note, velocity))
            pending.append((HostTime.adding(event.time + event.duration, to: start), event.note, nil))
        }
        pending.sort { $0.time < $1.time }
        startTimer()
    }

    func previewNote(_ note: Int) {
        preview([NoteEvent(note: note, time: 0, duration: 0.8)])
    }

    /// Sends one note so you can check a synth is listening.
    func sendTestNote() {
        previewNote(60)
    }

    /// MIDI destinations that can be chosen in Settings.
    func midiDestinations() -> [MIDIDestination] {
        MIDIOutput.destinations()
    }

    // MARK: - Scheduling

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func stopTimerIfIdle() {
        guard !transport.isPlaying, pending.isEmpty else { return }
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let horizon = HostTime.adding(lookahead, to: HostTime.now)

        if transport.isPlaying {
            scheduleClicks(until: horizon)
        }

        if !pending.isEmpty, let midi = midiOutput() {
            midi.channel = UInt8(max(1, min(16, settings.midiChannel)) - 1)
            while let next = pending.first, next.time <= horizon {
                pending.removeFirst()
                if let velocity = next.velocity {
                    midi.noteOn(next.note, velocity: velocity, at: next.time)
                } else {
                    midi.noteOff(next.note, at: next.time)
                }
            }
        }

        stopTimerIfIdle()
    }

    private func scheduleClicks(until horizon: UInt64) {
        let until = transport.position(at: horizon)
        defer { clicksScheduledUntil = max(clicksScheduledUntil, until) }

        // Count-in clicks always sound; after that only when the metronome is on
        let wanted = Metronome.clicks(from: clicksScheduledUntil, to: until, beatsPerBar: transport.beatsPerBar)
            .filter { transport.isMetronomeOn || $0.beat < 0 }
        guard !wanted.isEmpty, let clicks = clickPlayer() else { return }

        clicks.volume = Float(settings.metronomeVolume)
        for click in wanted {
            clicks.click(accent: click.isAccent, atHostTime: transport.hostTime(forBeat: Double(click.beat)))
        }
    }

    // MARK: - Devices, created on first use

    private func midiOutput() -> MIDIOutput? {
        if midi == nil {
            do {
                midi = try MIDIOutput(name: "Spot")
            } catch {
                problem = "MIDI is unavailable: \(error)"
            }
        }
        if midi?.destinationID != settings.midiDestinationID {
            midi?.destinationID = settings.midiDestinationID
        }
        return midi
    }

    private func clickPlayer() -> ClickPlayer? {
        let player = clicks ?? ClickPlayer()
        clicks = player
        do {
            try player.start()
            return player
        } catch {
            problem = "The metronome couldn't start audio: \(error.localizedDescription)"
            return nil
        }
    }
}
