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
/// A sequence ready to play: where it ends or loops, the recording and the takes.
struct SequencePlayback {
    var length: Double
    var loop: BeatRange?
    /// The recording, already lined up with the grid.
    var audio: RenderedAudio?
    var audioGain: Float = 1
    /// Your recorded takes, played as they were recorded.
    var takes: [TakePlayback] = []
}

struct TakePlayback {
    var id: UUID
    var url: URL
    var startBeat: Double
    /// The tempo it was played at.
    var tempo: Double
    var volume: Float
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
    /// Clicks and audio are scheduled up to (but not including) this beat.
    @ObservationIgnored private var scheduledUntil: Double = 0
    /// Clicks before this beat are the count-in, and sound even with the metronome off.
    @ObservationIgnored private var countInEnd: Double = 0
    @ObservationIgnored private var countInStart: Double = 0
    @ObservationIgnored private var sequence: SequencePlayback?
    @ObservationIgnored private var track: TrackPlayer?
    /// Audio is queued up to this beat; nil until the first slice has started.
    @ObservationIgnored private var audioCursor: Double?
    @ObservationIgnored private var audioRate: Double = 1
    @ObservationIgnored private var takePlayers: [UUID: TakePlayer] = [:]
    @ObservationIgnored private var takesStarted = false

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

    /// The metronome on its own, counting from beat 0.
    func play() {
        transport.barOrigin = 0
        play(from: 0)
    }

    /// Plays a sequence from `beat`, after the count-in (skipped when resuming from a pause).
    func play(_ sequence: SequencePlayback, from beat: Double, id: UUID, countIn: Bool = true) {
        if transport.isPlaying {
            stop()
        }
        self.sequence = sequence
        playingSequence = id
        play(from: beat, countIn: countIn)
    }

    /// Swaps in an edited sequence (a new render, loop or takes) while playing.
    func update(_ sequence: SequencePlayback, id: UUID) {
        guard playingSequence == id else { return }
        self.sequence = sequence
    }

    private func play(from beat: Double, countIn useCountIn: Bool = true) {
        // A count-in is clicks, so it only happens with the metronome on
        // The count-in is off for now: playback always starts straight away
        // let countIn = useCountIn && transport.isMetronomeOn ? Double(settings.countInBars * transport.beatsPerBar) : 0
        let countIn = 0.0
        transport.start(atBeat: beat - countIn, hostTime: HostTime.adding(startLatency, to: HostTime.now))
        scheduledUntil = beat - countIn
        countInStart = beat - countIn
        countInEnd = beat
        audioCursor = nil
        takesStarted = false
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
        track?.stop()
        audioCursor = nil
        stopTakes()
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
            transport.jump(toBeat: loop.start, atHostTime: loopEndTime)
            scheduledUntil = loop.start
            // Any count-in is long over: looping back before where playback started mustn't count as one
            // (its clicks would sound with the metronome off)
            countInEnd = -.infinity
            // Audio carries straight on from the loop start, queued after the slice that ended at the loop end
            if audioCursor != nil {
                audioCursor = loop.start
            }
            if takesStarted {
                stopTakes()
                startTakes(fromBeat: loop.start, atHostTime: loopEndTime)
            }
            until = transport.position(at: horizon)
        }
        
        scheduleWindow(from: scheduledUntil, to: until)
        scheduledUntil = max(scheduledUntil, until)
    }
    
    private func scheduleWindow(from: Double, to: Double) {
        guard to > from else { return }
        scheduleClicks(from: from, to: to)
        if let sequence, let audio = sequence.audio {
            scheduleAudio(audio, gain: sequence.audioGain, loopEnd: sequence.loop?.end, from: from, to: to)
        }
        if sequence != nil, !takesStarted, countInEnd < to {
            takesStarted = true
            let beat = countInEnd.isFinite ? countInEnd : from
            startTakes(fromBeat: beat, atHostTime: transport.hostTime(forBeat: beat))
        }
    }
    
    /// Starts every take that's playing at `beat` (or later), at the right point in each.
    private func startTakes(fromBeat beat: Double, atHostTime hostTime: UInt64) {
        guard let takes = sequence?.takes else { return }
        for take in takes {
            do {
                let player = try takePlayers[take.id] ?? TakePlayer(url: take.url)
                takePlayers[take.id] = player
                // At practice speed the clock runs slower than the take was played; slow the take to match
                let rate = Float(Double(transport.bpm) / take.tempo)
                if beat >= take.startBeat {
                    try player.play(from: (beat - take.startBeat) * 60 / take.tempo, atHostTime: hostTime, rate: rate, volume: take.volume)
                } else {
                    try player.play(from: 0, atHostTime: transport.hostTime(forBeat: take.startBeat), rate: rate, volume: take.volume)
                }
            } catch {
                problem = "Couldn't play a recorded take: \(error.localizedDescription)"
            }
        }
    }
    
    private func stopTakes() {
        takePlayers.values.forEach { $0.stop() }
    }
    
    /// Queues the recording in one-beat slices. The first starts at an exact time when the count-in ends;
    /// the rest follow on back to back, so loops and slices join without gaps.
    private func scheduleAudio(_ audio: RenderedAudio, gain: Float, loopEnd: Double?, from: Double, to: Double) {
        // Fallen behind (the audio was missing for a while, e.g. while it re-rendered): queuing the gap
        // would make it late, so start it again from here
        if let cursor = audioCursor, cursor < from - 1e-6 {
            audioCursor = nil
        }
        if audioCursor == nil {
            // From the very start, audio before bar 1 (a pickup) plays during the count-in. Audio that
            // arrives once playback is under way (it was still rendering) joins in now, not back at the start.
            let start = countInEnd <= 0.001 ? max(countInStart, min(audio.startBeat, countInEnd)) : countInEnd
            let first = max(start, from)
            guard first < to else { return }
            // The loop end only counts if we start before it (clicking past a loop plays on from there)
            let end = min(floor(first) + 1, loopEnd.map { first < $0 ? $0 : .infinity } ?? .infinity)
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
        // Beats (and bar accents) count from the bar origin, i.e. a sequence's 1.1.1.
        // Count-in clicks always sound; after that only when the metronome is on
        let origin = transport.barOrigin
        let wanted = Metronome.clicks(from: from - origin, to: to - origin, beatsPerBar: transport.beatsPerBar)
            .filter { transport.isMetronomeOn || Double($0.beat) + origin < countInEnd }
        guard !wanted.isEmpty, let clicks = clickPlayer() else { return }

        clicks.volume = Float(settings.metronomeVolume)
        for click in wanted {
            clicks.click(accent: click.isAccent, atHostTime: transport.hostTime(forBeat: Double(click.beat) + origin))
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
