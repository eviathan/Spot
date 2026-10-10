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
/// A sequence's backing ready to play: notes in beats, plus where it ends or loops.
struct SequencePlayback {
    var notes: [BeatNote]
    var length: Double
    var loop: BeatRange?
    /// The recording, already lined up with the grid.
    var audio: RenderedAudio?
    var audioGain: Float = 1
}

@Observable
final class PlaybackController {
    let transport: TransportState
    let settings: AudioSettings
    /// Set when MIDI or audio couldn't start, for the Settings tab to show.
    private(set) var problem: String?
    /// Which sequence window is playing, if any.
    private(set) var playingSequence: UUID?

    @ObservationIgnored private var midi: MIDIOutput?
    @ObservationIgnored private var clicks: ClickPlayer?
    @ObservationIgnored private var timer: DispatchSourceTimer?
    /// MIDI messages waiting to be sent, kept in time order.
    @ObservationIgnored private var pending: [(time: UInt64, note: Int, velocity: Int?)] = []
    /// Clicks and sequence notes are scheduled up to (but not including) this beat.
    @ObservationIgnored private var scheduledUntil: Double = 0
    /// Clicks before this beat are the count-in, and sound even with the metronome off.
    @ObservationIgnored private var countInEnd: Double = 0
    @ObservationIgnored private var sequence: SequencePlayback?
    /// Notes already sounding at this beat start here too (playing from the middle of a chord, or looping).
    @ObservationIgnored private var carryInBeat: Double?
    /// Sequence notes sounding now, by note number, so a loop or stop can cut them off.
    @ObservationIgnored private var sounding: [Int: Int] = [:]
    @ObservationIgnored private var track: TrackPlayer?
    /// Audio is queued up to this beat; nil until the first slice has started.
    @ObservationIgnored private var audioCursor: Double?
    @ObservationIgnored private var audioRate: Double = 1

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
        play(from: 0)
    }

    /// Plays a sequence's backing from `beat`, after the count-in.
    func play(_ sequence: SequencePlayback, from beat: Double, id: UUID) {
        if transport.isPlaying {
            stop()
        }
        self.sequence = sequence
        playingSequence = id
        play(from: beat)
    }

    /// Swaps in edited backing while playing; anything already sent still sounds.
    func update(_ sequence: SequencePlayback, id: UUID) {
        guard playingSequence == id else { return }
        self.sequence = sequence
    }

    private func play(from beat: Double) {
        let countIn = Double(settings.countInBars * transport.beatsPerBar)
        transport.start(atBeat: beat - countIn, hostTime: HostTime.adding(startLatency, to: HostTime.now))
        scheduledUntil = beat - countIn
        countInEnd = beat
        carryInBeat = beat
        audioCursor = nil
        startTimer()
    }

    /// Practice speed for the audio (the clock is slowed separately, via the tempo).
    func setAudioRate(_ rate: Double) {
        audioRate = rate
        track?.rate = Float(rate)
    }
    
    func stop() {
        sequence = nil
        playingSequence = nil
        sounding.removeAll()
        track?.stop()
        audioCursor = nil
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
            schedule(until: horizon)
            if transport.isPlaying, let sequence, sequence.loop == nil, transport.position() >= sequence.length {
                stop()
                return
            }
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

    private func schedule(until horizon: UInt64) {
        var until = transport.position(at: horizon)
        
        // Reaching the end of a loop: play up to it, then move the clock back to the loop start at that moment
        if let loop = sequence?.loop, loop.length > 0, until >= loop.end, scheduledUntil < loop.end {
            scheduleWindow(from: scheduledUntil, to: loop.end)
            let loopEndTime = transport.hostTime(forBeat: loop.end)
            releaseSounding(at: loopEndTime)
            transport.jump(toBeat: loop.start, atHostTime: loopEndTime)
            scheduledUntil = loop.start
            // Audio carries straight on from the loop start, queued after the slice that ended at the loop end
            if audioCursor != nil {
                audioCursor = loop.start
            }
            carryInBeat = loop.start
            until = transport.position(at: horizon)
        }
        
        scheduleWindow(from: scheduledUntil, to: until)
        scheduledUntil = max(scheduledUntil, until)
    }
    
    private func scheduleWindow(from: Double, to: Double) {
        guard to > from else { return }
        scheduleClicks(from: from, to: to)
        if let sequence, let midi = midiOutput() {
            scheduleNotes(sequence, from: from, to: to, midi: midi)
        }
        if let sequence, let audio = sequence.audio {
            scheduleAudio(audio, gain: sequence.audioGain, loopEnd: sequence.loop?.end, to: to)
        }
    }
    
    /// Queues the recording in one-beat slices. The first starts at an exact time when the count-in ends;
    /// the rest follow on back to back, so loops and slices join without gaps.
    private func scheduleAudio(_ audio: RenderedAudio, gain: Float, loopEnd: Double?, to: Double) {
        if audioCursor == nil {
            guard countInEnd < to else { return }
            let first = countInEnd
            let end = min(floor(first) + 1, loopEnd ?? .infinity)
            guard let slice = audio.buffer(fromBeat: first, toBeat: end) else { return }
            let player = track ?? TrackPlayer()
            track = player
            player.rate = Float(audioRate)
            player.volume = gain
            do {
                try player.start(slice, atHostTime: transport.hostTime(forBeat: first))
            } catch {
                problem = "Couldn't play the audio: \(error.localizedDescription)"
                return
            }
            audioCursor = end
        }
        
        track?.volume = gain
        while let cursor = audioCursor, cursor < to {
            let end = min(floor(cursor) + 1, loopEnd.map { cursor < $0 ? $0 : .infinity } ?? .infinity)
            guard let slice = audio.buffer(fromBeat: cursor, toBeat: end) else { break }
            track?.append(slice)
            audioCursor = end
        }
    }
    
    private func scheduleClicks(from: Double, to: Double) {
        // Count-in clicks always sound; after that only when the metronome is on
        let wanted = Metronome.clicks(from: from, to: to, beatsPerBar: transport.beatsPerBar)
            .filter { transport.isMetronomeOn || Double($0.beat) < countInEnd }
        guard !wanted.isEmpty, let clicks = clickPlayer() else { return }

        clicks.volume = Float(settings.metronomeVolume)
        for click in wanted {
            clicks.click(accent: click.isAccent, atHostTime: transport.hostTime(forBeat: Double(click.beat)))
        }
    }
    
    private func scheduleNotes(_ sequence: SequencePlayback, from: Double, to: Double, midi: MIDIOutput) {
        midi.channel = UInt8(max(1, min(16, settings.midiChannel)) - 1)
        var ons: [(beat: Double, note: BeatNote)] = []
        
        if let carry = carryInBeat, carry >= from, carry < to {
            ons += sequence.notes.filter { $0.start < carry && $0.end > carry }.map { (carry, $0) }
            carryInBeat = nil
        }
        // Nothing sounds during the count-in, even if the count-in overlaps earlier chords
        ons += sequence.notes.filter { $0.start >= max(from, countInEnd) && $0.start < to }.map { ($0.start, $0) }
        
        for (beat, note) in ons {
            midi.noteOn(note.note, velocity: note.velocity, at: transport.hostTime(forBeat: beat))
            sounding[note.note, default: 0] += 1
        }
        for note in sequence.notes where note.end >= from && note.end < to && (sounding[note.note] ?? 0) > 0 {
            midi.noteOff(note.note, at: transport.hostTime(forBeat: note.end))
            sounding[note.note]! -= 1
        }
    }
    
    private func releaseSounding(at time: UInt64) {
        guard let midi = midiOutput() else { return }
        for (note, count) in sounding where count > 0 {
            for _ in 0..<count {
                midi.noteOff(note, at: time)
            }
        }
        sounding.removeAll()
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
