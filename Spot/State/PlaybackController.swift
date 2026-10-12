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
    /// The recording: it follows the clock by itself, told only where to start and where a loop goes round.
    @ObservationIgnored private var track: TrackPlayer?
    /// The loop's last time round, as the clock was told: a recording that starts playing before then needs telling
    /// too.
    @ObservationIgnored private var lastJump: (at: Double, to: Double, time: UInt64)?
    @ObservationIgnored private var audioRate: Double = 1
    @ObservationIgnored private var takePlayers: [UUID: TakePlayer] = [:]
    @ObservationIgnored private var takesStarted = false

    /// Notes are sent this far ahead (seconds), stamped with when they should sound. Short when they also go to a
    /// MIDI device (some play notes when they arrive); longer when only Spot's own sound (and apps reading the
    /// Spot source, which keep to the stamps) plays them, so a busy moment on the main thread doesn't drop them.
    private var lookahead: Double { settings.midiDestinationID == nil ? 0.4 : 0.1 }
    /// The metronome is queued this far ahead (seconds): its clicks are played by the audio engine at their times,
    /// so they can be, and then a busy moment on the main thread (resizing the window, scrolling, a big redraw)
    /// doesn't leave a gap. While looping, only up to the loop's end (see scheduleAhead).
    private let bufferedLookahead = 1.0
    /// Clicks are queued up to this beat.
    @ObservationIgnored private var clicksUntil: Double = 0
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

    /// Practice speed: a sequence or tab plays at this fraction of its tempo (0.75 for 75%), the tempo itself left
    /// as it is. Just for now: not saved.
    private(set) var practiceSpeed: Double = 1

    static let practiceSpeeds: [Double] = [0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1, 1.1, 1.25]

    /// Changes the practice speed, while playing too: the clock, the recording and what's queued follow.
    func setPracticeSpeed(_ speed: Double) {
        let speed = min(max((speed * 100).rounded() / 100, 0.25), 1.5)
        guard speed != practiceSpeed else { return }
        let old = practiceSpeed
        practiceSpeed = speed
        guard transport.isPlaying, tab != nil || playingSequence != nil else { return }
        transport.setBPM(transport.bpm / old * speed)
        setAudioRate(audioRate / old * speed)
        // Clicks queued ahead were timed at the old speed
        clicks?.stop()
        clicksUntil = scheduledUntil
    }

    func play(tab: TabPerformance, from time: Double) {
        if transport.isPlaying {
            stop()
        }
        self.tab = tab
        isPlayingTab = true
        // The tab's times are in seconds, so the transport counts seconds as beats; the metronome's tempo comes
        // back afterwards
        bpmBeforeTab = transport.bpm
        transport.setBPM(60 * practiceSpeed)
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
        let old = self.sequence
        self.sequence = sequence
        guard transport.isPlaying else { return }

        // A new render (crossfaded in where it's up to), or the recording muted or back
        track?.volume = sequence.audioGain
        if !PlaybackController.isSameAudio(old?.audio, sequence.audio) {
            if let audio = sequence.audio, old?.audio != nil, let track {
                do {
                    try track.replace(with: audio)
                } catch {
                    problem = "Couldn't play the audio: \(error.localizedDescription)"
                }
            } else if let audio = sequence.audio {
                // Arriving once playback is under way (it was still rendering, or was muted): it joins in now
                let time = HostTime.adding(startLatency, to: HostTime.now)
                startTrack(audio, gain: sequence.audioGain, atBeat: transport.position(at: time), hostTime: time)
            } else {
                track?.stop()
            }
        }

        // A new loop end before the clicks queued so far (they go up to the old one): queue them again from just
        // ahead of now. (Unless the clock is already set to play on past it, as it does past a loop end it's
        // been scheduled beyond.)
        guard old?.loop != sequence.loop, let loop = sequence.loop, let clicks else { return }
        let playhead = transport.position()
        guard playhead < loop.end, scheduledUntil < loop.end, loop.end < clicksUntil else { return }
        clicks.clear()
        let resume = transport.position(at: HostTime.adding(startLatency, to: HostTime.now))
        clicksUntil = resume
        // Up to where everything else is scheduled now, so the next tick carries on from there
        if resume < scheduledUntil {
            scheduleClicks(from: resume, to: scheduledUntil)
            clicksUntil = scheduledUntil
        }
    }

    /// Whether two renders are the same one. Comparing the samples would take too long, so: their first channel's
    /// storage (an edit to a render copies it, as the player holds on to the one it's playing).
    private static func isSameAudio(_ a: RenderedAudio?, _ b: RenderedAudio?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        let storage = { (audio: RenderedAudio) in audio.audio.channels.first?.withUnsafeBufferPointer { $0.baseAddress } }
        return a.tempo == b.tempo && a.startBeat == b.startBeat && a.audio.frameCount == b.audio.frameCount
            && storage(a) == storage(b)
    }

    private func startTrack(_ audio: RenderedAudio, gain: Float, atBeat beat: Double, hostTime: UInt64) {
        let player = track ?? TrackPlayer()
        track = player
        player.rate = Float(audioRate)
        player.volume = gain
        do {
            try player.start(audio, atBeat: beat, hostTime: hostTime)
        } catch {
            problem = "Couldn't play the audio: \(error.localizedDescription)"
            return
        }
        // A loop's going round already set up on the clock, still to come
        if let lastJump, lastJump.time > hostTime {
            player.jump(at: lastJump.at, to: lastJump.to)
        }
    }

    private func play(from beat: Double, countIn useCountIn: Bool = true) {
        // A count-in is clicks, so it only happens with the metronome on
        // The count-in is off for now: playback always starts straight away
        // let countIn = useCountIn && transport.isMetronomeOn ? Double(settings.countInBars * transport.beatsPerBar) : 0
        let countIn = 0.0
        let startTime = HostTime.adding(startLatency, to: HostTime.now)
        transport.start(atBeat: beat - countIn, hostTime: startTime)
        scheduledUntil = beat - countIn
        countInStart = beat - countIn
        countInEnd = beat
        clicksUntil = beat - countIn
        lastJump = nil
        takesStarted = false
        if let sequence, let audio = sequence.audio {
            startTrack(audio, gain: sequence.audioGain, atBeat: beat - countIn, hostTime: startTime)
        }
        startTimer()
    }

    /// Practice speed for the audio (the clock is slowed separately, via the tempo).
    func setAudioRate(_ rate: Double) {
        audioRate = rate
        track?.rate = Float(rate)
    }
    
    func stop() {
        // A sequence played at practice speed: the clock back to its own tempo
        if playingSequence != nil, tab == nil, practiceSpeed != 1 {
            transport.setBPM(transport.bpm / practiceSpeed)
        }
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
        lastJump = nil
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
            // The recording goes round with it, crossfaded, when it gets there
            track?.jump(at: loop.end, to: loop.start)
            lastJump = (loop.end, loop.start, loopEndTime)
            scheduledUntil = loop.start
            // Any count-in is long over: looping back before where playback started mustn't count as one
            // (its clicks would sound with the metronome off)
            countInEnd = -.infinity
            // Clicks were queued up to the loop end (see scheduleAhead): on from the start now
            clicksUntil = loop.start
            if takesStarted {
                stopTakes()
                startTakes(fromBeat: loop.start, atHostTime: loopEndTime)
            }
            until = transport.position(at: horizon)
        }
        
        scheduleWindow(from: scheduledUntil, to: until)
        scheduledUntil = max(scheduledUntil, until)
        scheduleAhead()
    }

    /// The clicks, further ahead than the rest. While looping, only up to the loop's end: after it they're queued
    /// once the clock has been set to go back (they'd be wrong if the loop changed before then).
    private func scheduleAhead() {
        guard tab == nil else { return }
        var target = transport.position(at: HostTime.adding(bufferedLookahead, to: HostTime.now))
        if let loop = sequence?.loop, loop.length > 0, scheduledUntil < loop.end {
            target = min(target, loop.end)
        }
        if target > clicksUntil {
            scheduleClicks(from: clicksUntil, to: target)
            clicksUntil = target
        }
    }

    private func scheduleWindow(from: Double, to: Double) {
        guard to > from else { return }
        if let tab {
            scheduleTab(tab, from: from, to: to)
            return
        }
        // (Clicks are usually queued already, further ahead: see scheduleAhead)
        if to > clicksUntil {
            scheduleClicks(from: max(from, clicksUntil), to: to)
            clicksUntil = to
        }
        if let sequence, let tab = sequence.tab {
            scheduleLinkedTab(tab, startingAt: sequence.tabStart, from: from, to: to)
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
