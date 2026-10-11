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
    /// A linked tab, timed in quarter notes (beats), and the beat it starts on.
    var tab: TabPerformance?
    var tabStart: Double = 0
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
    /// A tab playing (on its own clock: one beat is a second), and how far through its events and clicks.
    @ObservationIgnored private var tab: TabPerformance?
    @ObservationIgnored private var tabEvent = 0
    @ObservationIgnored private var tabClick = 0
    private(set) var isPlayingTab = false
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
        if let tab = sequence.tab {
            sendSetup(of: tab, at: HostTime.now)
        }
        play(from: beat, countIn: countIn)
    }

    /// A tab's sounds and bend ranges, which have to be in place wherever it starts playing.
    private func sendSetup(of tab: TabPerformance, at time: UInt64) {
        guard midiOutput() != nil else { return }
        for event in tab.events where event.time == 0 {
            switch event.message {
            case .program, .controller, .pitchBend: send(event.message, at: time)
            default: break
            }
        }
    }

    /// Stops every note a tab started, and takes off any bend.
    private func silence(_ tab: TabPerformance, at time: UInt64? = nil) {
        guard let midi = midiOutput() else { return }
        for channel in tab.channels {
            midi.channel = UInt8(channel)
            midi.controlChange(123, value: 0, at: time ?? 0)
            midi.pitchBend(8192, at: time ?? 0)
        }
    }

    /// A linked tab's events between two beats.
    private func scheduleLinkedTab(_ tab: TabPerformance, startingAt start: Double, from: Double, to: Double) {
        // The first event at or after `from` (events are in time order)
        var low = 0, high = tab.events.count
        while low < high {
            let middle = (low + high) / 2
            if tab.events[middle].time + start < from - 1e-9 { low = middle + 1 } else { high = middle }
        }
        var index = low
        while index < tab.events.count, tab.events[index].time + start < to - 1e-9 {
            let event = tab.events[index]
            index += 1
            // The sounds and bend ranges were set when playback began
            if event.time == 0 {
                switch event.message {
                case .program, .controller, .pitchBend: continue
                default: break
                }
            }
            send(event.message, at: transport.hostTime(forBeat: event.time + start))
        }
    }

    /// Plays a tab from `time` seconds in. The clock runs at 60 bpm, so its beats are the tab's seconds.
    @ObservationIgnored private var bpmBeforeTab: Double?

    func play(tab: TabPerformance, from time: Double) {
        if transport.isPlaying {
            stop()
        }
        self.tab = tab
        isPlayingTab = true
        // The tab's times are in seconds, so the transport counts seconds as beats; the metronome's tempo comes
        // back afterwards
        bpmBeforeTab = transport.bpm
        transport.setBPM(60)
        transport.barOrigin = 0
        let start = HostTime.adding(startLatency, to: HostTime.now)
        // Every channel's sound and bend range, wherever it starts
        if midiOutput() != nil {
            for event in tab.events where event.time == 0 {
                switch event.message {
                case .program, .controller, .pitchBend: send(event.message, at: start)
                default: break
                }
            }
        }
        tabEvent = tab.events.firstIndex { $0.time >= time - 0.0005 } ?? tab.events.count
        tabClick = tab.clicks.firstIndex { $0.time >= time - 0.0005 } ?? tab.clicks.count
        transport.start(atBeat: time, hostTime: start)
        scheduledUntil = time
        countInStart = time
        countInEnd = time
        startTimer()
    }

    private func send(_ message: TabPerformance.Message, at time: UInt64) {
        guard let midi = midiOutput() else { return }
        switch message {
        case .noteOn(let channel, let note, let velocity):
            midi.channel = UInt8(channel)
            midi.noteOn(note, velocity: velocity, at: time)
        case .noteOff(let channel, let note):
            midi.channel = UInt8(channel)
            midi.noteOff(note, at: time)
        case .pitchBend(let channel, let value):
            midi.channel = UInt8(channel)
            midi.pitchBend(value, at: time)
        case .program(let channel, let program):
            midi.channel = UInt8(channel)
            midi.programChange(program, at: time)
        case .controller(let channel, let number, let value):
            midi.channel = UInt8(channel)
            midi.controlChange(number, value: value, at: time)
        }
    }

    /// The tab's events and (with the metronome on) clicks due before `to`.
    private func scheduleTab(_ tab: TabPerformance, from: Double, to: Double) {
        while tabEvent < tab.events.count, tab.events[tabEvent].time < to {
            let event = tab.events[tabEvent]
            tabEvent += 1
            send(event.message, at: transport.hostTime(forBeat: event.time))
        }
        let clicks = transport.isMetronomeOn ? clickPlayer() : nil
        clicks?.volume = Float(settings.metronomeVolume)
        while tabClick < tab.clicks.count, tab.clicks[tabClick].time < to {
            let click = tab.clicks[tabClick]
            tabClick += 1
            clicks?.click(accent: click.isAccent, atHostTime: transport.hostTime(forBeat: click.time))
        }
    }

    /// Swaps in an edited sequence (a new render, loop or takes) while playing.
    func update(_ sequence: SequencePlayback, id: UUID) {
        guard playingSequence == id else { return }
        // The tab muted, unlinked or changed: stop what it was playing (the new one carries on from here)
        if let old = self.sequence?.tab, sequence.tab == nil || sequence.tab?.events != old.events || sequence.tabStart != self.sequence?.tabStart {
            silence(old)
            if let tab = sequence.tab { sendSetup(of: tab, at: HostTime.now) }
        } else if self.sequence?.tab == nil, let tab = sequence.tab {
            sendSetup(of: tab, at: HostTime.now)
        }
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
        // Silence and unbend every channel a tab used
        if let tab = tab ?? sequence?.tab {
            silence(tab)
        }
        tab = nil
        isPlayingTab = false
        if let bpmBeforeTab {
            transport.setBPM(bpmBeforeTab)
            self.bpmBeforeTab = nil
        }
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
            if transport.isPlaying, let tab, transport.position() >= tab.length + 0.3 {
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
            // Notes held over the loop end would otherwise never stop
            if let tab = sequence?.tab {
                silence(tab, at: loopEndTime)
            }
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
        if let tab {
            scheduleTab(tab, from: from, to: to)
            return
        }
        scheduleClicks(from: from, to: to)
        if let sequence, let tab = sequence.tab {
            scheduleLinkedTab(tab, startingAt: sequence.tabStart, from: from, to: to)
        }
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
        let wanted = Metronome.clicks(from: from - origin, to: to - origin, timeSignature: transport.timeSignature)
            .filter { transport.isMetronomeOn || $0.beat + origin < countInEnd }
        guard !wanted.isEmpty, let clicks = clickPlayer() else { return }

        clicks.volume = Float(settings.metronomeVolume)
        for click in wanted {
            clicks.click(accent: click.isAccent, atHostTime: transport.hostTime(forBeat: click.beat + origin))
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
        updateSynth()
        return midi
    }

    /// Spot's own sound, on or off, with the SoundFont and volume chosen in Settings.
    @ObservationIgnored private var synth: SoftSynth?
    @ObservationIgnored private var synthBank: Data??

    private func updateSynth() {
        guard settings.usesBuiltInSound else {
            if synth != nil {
                synth?.allNotesOff()
                synth = nil
                midi?.synth = nil
                synthBank = nil
            }
            return
        }
        if synth == nil {
            do {
                synth = try SoftSynth()
            } catch {
                problem = "Spot's own sound couldn't start: \(error.localizedDescription)"
                return
            }
        }
        if synthBank != .some(settings.soundFontBookmark) {
            synthBank = .some(settings.soundFontBookmark)
            let url = settings.soundFontURL
            let accessing = url?.startAccessingSecurityScopedResource() ?? false
            defer { if accessing { url?.stopAccessingSecurityScopedResource() } }
            do {
                try synth?.loadSoundBank(url)
            } catch {
                problem = error.localizedDescription
            }
        }
        synth?.volume = Float(settings.builtInSoundVolume)
        if midi?.synth !== synth {
            midi?.synth = synth
        }
    }

    /// Applies a change made in Settings to Spot's own sound straight away.
    func soundSettingsChanged() {
        _ = midiOutput()
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
