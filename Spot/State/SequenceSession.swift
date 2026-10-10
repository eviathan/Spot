//
//  SequenceSession.swift
//  Spot
//

import Foundation
import Observation
import AVFoundation
import SpotCore

/// The sequence open in the Sequence tab and the `.spot` file behind it.
///
/// Saved files are written a moment after every change. A sequence that hasn't been saved yet is kept
/// in the app's preferences so it survives a restart, and the last file is reopened at launch.
@Observable
final class SequenceSession {
    /// Where the sequence's audio is up to.
    enum AudioStatus: Equatable {
        case none
        case loading
        case ready
        /// The file couldn't be found; the user can locate it.
        case missing
        case failed(String)
    }
    
    struct Recent: Codable, Hashable, Identifiable {
        var name: String
        var bookmark: Data
        var id: Data { bookmark }
    }

    let library: LibraryStore
    let playback: PlaybackController
    let transport: TransportState

    /// nil when nothing is open.
    var sequence: ChordSequence? {
        didSet { sequenceChanged(from: oldValue) }
    }
    private(set) var editor: SequenceEditorState?
    private(set) var fileURL: URL?
    private(set) var hasUnsavedChanges = false
    private(set) var saveError: String?
    private(set) var recents: [Recent] = []
    
    private(set) var audioStatus: AudioStatus = .none
    /// Set when a relinked file isn't the recording the sequence was made with.
    private(set) var audioWarning: String?
    private(set) var peaks: WaveformPeaks?
    /// The audio lined up with the grid, ready to play; nil while it's being (re)rendered.
    private(set) var rendered: RenderedAudio?
    /// 0...1 while rendering.
    private(set) var renderProgress: Double?
    /// What was heard in the recording: tempo, beats, bar 1, chords, key. Nothing changes until it's applied.
    private(set) var analysis: AudioAnalysis?
    /// 0...1 while analysing.
    private(set) var analysisProgress: Double?
    var showsAnalysis = true
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    
    @ObservationIgnored private var sourceAudio: AudioData?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderDelay: DispatchWorkItem?
    @ObservationIgnored private var taps: [Date] = []

    @ObservationIgnored private var autosave: DispatchWorkItem?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let recentsKey = "sequence.recents"
    private static let lastFileKey = "sequence.lastFile"
    private static let draftKey = "sequence.untitledDraft"

    init(library: LibraryStore, playback: PlaybackController, transport: TransportState) {
        self.library = library
        self.playback = playback
        self.transport = transport
        recents = (defaults.data(forKey: SequenceSession.recentsKey))
            .flatMap { try? JSONDecoder().decode([Recent].self, from: $0) } ?? []
        restore()
    }

    var isOpen: Bool {
        sequence != nil
    }

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    /// True when closing would lose work: an unsaved sequence with something in it.
    var needsSaveBeforeClosing: Bool {
        guard let sequence, fileURL == nil else { return false }
        return !sequence.chords.isEmpty || !sequence.sections.isEmpty
    }

    var isPlaying: Bool {
        editor.map { playback.playingSequence == $0.id } ?? false
    }

    // MARK: - Opening and closing

    func newSequence() {
        close()
        load(ChordSequence(), from: nil)
        hasUnsavedChanges = false
    }

    /// Opens a `.spot` package the user chose (or that was double-clicked in Finder).
    func open(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let data = try Data(contentsOf: url.appendingPathComponent(SequenceDocument.sequenceFilename))
            let sequence = try JSONDecoder().decode(ChordSequence.self, from: data)
            close()
            load(sequence, from: url)
            remember(url)
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func open(_ recent: Recent) throws {
        var isStale = false
        let url = try URL(resolvingBookmarkData: recent.bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
        try open(url)
    }

    func removeRecent(_ recent: Recent) {
        recents.removeAll { $0 == recent }
        saveRecents()
    }

    /// Closes the sequence (saving it first if it has a file).
    func close() {
        if isPlaying {
            playback.stop()
        }
        if fileURL != nil, hasUnsavedChanges {
            try? save()
        }
        autosave?.cancel()
        fileURL?.stopAccessingSecurityScopedResource()
        fileURL = nil
        editor = nil
        unloadAudio()
        isLoading = true
        sequence = nil
        isLoading = false
        hasUnsavedChanges = false
        saveError = nil
        defaults.removeObject(forKey: SequenceSession.lastFileKey)
        defaults.removeObject(forKey: SequenceSession.draftKey)
    }

    private func load(_ sequence: ChordSequence, from url: URL?) {
        let editor = SequenceEditorState(library: library)
        editor.snap = Double(sequence.beatsPerBar)
        editor.analyse(sequence)
        editor.select(beat: 0, extend: false, in: sequence)
        self.editor = editor
        fileURL = url
        isLoading = true
        self.sequence = sequence
        isLoading = false
        hasUnsavedChanges = false
        saveError = nil
        loadAudio()
    }
    
    // MARK: - Saving

    /// Writes the sequence into its package, leaving any other files there alone.
    func save() throws {
        guard let sequence, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            try sequence.encoded().write(to: fileURL.appendingPathComponent(SequenceDocument.sequenceFilename), options: .atomic)
            hasUnsavedChanges = false
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            throw error
        }
    }

    /// Call after Save As has written a new package (with `SequenceDocument`): this becomes the file.
    func didSave(to url: URL) {
        if fileURL != url {
            fileURL?.stopAccessingSecurityScopedResource()
            _ = url.startAccessingSecurityScopedResource()
            fileURL = url
        }
        hasUnsavedChanges = false
        saveError = nil
        defaults.removeObject(forKey: SequenceSession.draftKey)
        remember(url)
    }

    /// What Save As writes.
    var document: SequenceDocument? {
        sequence.map { SequenceDocument(sequence: $0) }
    }

    private func sequenceChanged(from old: ChordSequence?) {
        guard !isLoading, let sequence, sequence != old else { return }
        editor?.analyse(sequence)
        
        // The rendered audio depends on the markers, tempo and length
        if sequence.audio?.warpMarkers != old?.audio?.warpMarkers || sequence.tempo != old?.tempo
            || sequence.lengthInBars != old?.lengthInBars || sequence.beatsPerBar != old?.beatsPerBar {
            scheduleRender()
        }
        if isPlaying, let editor {
            playback.update(playbackData(sequence, editor: editor), id: editor.id)
            transport.setBPM(Int((sequence.tempo * sequence.practiceRate).rounded()))
            playback.setAudioRate(sequence.practiceRate)
        }
        hasUnsavedChanges = true
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if fileURL != nil {
                try? save()
            } else if let sequence, let data = try? sequence.encoded() {
                defaults.set(data, forKey: SequenceSession.draftKey)
            }
        }
        autosave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: - Remembering files

    private func remember(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        recents.removeAll { $0.name == name || $0.bookmark == bookmark }
        recents.insert(Recent(name: name, bookmark: bookmark), at: 0)
        recents = Array(recents.prefix(10))
        saveRecents()
        defaults.set(bookmark, forKey: SequenceSession.lastFileKey)
    }

    private func saveRecents() {
        defaults.set(try? JSONEncoder().encode(recents), forKey: SequenceSession.recentsKey)
    }

    /// Reopens the last file, or the unsaved draft.
    private func restore() {
        if let bookmark = defaults.data(forKey: SequenceSession.lastFileKey),
           let recent = recents.first(where: { $0.bookmark == bookmark }) ?? Optional(Recent(name: "", bookmark: bookmark)),
           (try? open(recent)) != nil {
            return
        }
        if let data = defaults.data(forKey: SequenceSession.draftKey),
           let draft = try? JSONDecoder().decode(ChordSequence.self, from: data) {
            load(draft, from: nil)
            hasUnsavedChanges = true
        }
    }

    // MARK: - Playing

    func togglePlay() {
        guard let sequence, let editor else { return }
        if isPlaying {
            playback.stop()
        } else {
            // Practice speed slows everything: the clock, the backing and the audio
            transport.setBPM(Int((sequence.tempo * sequence.practiceRate).rounded()))
            transport.beatsPerBar = sequence.beatsPerBar
            playback.setAudioRate(sequence.practiceRate)
            playback.play(playbackData(sequence, editor: editor), from: editor.selection.start, id: editor.id)
        }
    }
    
    private func playbackData(_ sequence: ChordSequence, editor: SequenceEditorState) -> SequencePlayback {
        var data = editor.playback(for: sequence)
        if let audio = sequence.audio, !audio.isMuted, rendered?.tempo == sequence.tempo {
            data.audio = rendered
            data.audioGain = Float(pow(10, audio.gain / 20))
        }
        return data
    }
    
    // MARK: - Audio
    
    /// Links a recording to the sequence (it stays where it is) and lengthens the sequence to fit it.
    func importAudio(_ url: URL) throws {
        let reference = try makeReference(url)
        let secondsPerBar = Double(sequence?.beatsPerBar ?? 4) * 60 / (sequence?.tempo ?? 120)
        sequence?.audio = AudioTrack(reference: reference)
        if let bars = sequence?.lengthInBars, Double(bars) * secondsPerBar < reference.duration {
            sequence?.setLength(bars: Int(ceil(reference.duration / secondsPerBar)))
        }
        audioWarning = nil
        loadAudio()
    }
    
    /// Points the sequence at a moved or renamed copy of its recording, warning if it's a different one.
    func relinkAudio(_ url: URL) throws {
        guard let old = sequence?.audio?.reference else { return try importAudio(url) }
        let reference = try makeReference(url)
        if reference.fingerprint != old.fingerprint {
            audioWarning = abs(reference.duration - old.duration) > 0.5
                ? "This is a different recording (\(Int(reference.duration)) s instead of \(Int(old.duration)) s). Warp markers may not line up."
                : "This file isn't identical to the original. Check that the warp markers still line up."
        } else {
            audioWarning = nil
        }
        sequence?.audio?.reference = reference
        loadAudio()
    }
    
    func removeAudio() {
        sequence?.audio = nil
        audioWarning = nil
        unloadAudio()
    }
    
    /// Records a tap; after a few, sets the tempo from their spacing. Taps more than 2 s apart start again.
    func tapTempo() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2 {
            taps.removeAll()
        }
        taps.append(now)
        taps = Array(taps.suffix(9))
        guard taps.count >= 4 else { return }
        let interval = taps.last!.timeIntervalSince(taps.first!) / Double(taps.count - 1)
        sequence?.tempo = min(max((60 / interval * 10).rounded() / 10, 20), 300)
    }
    
    var tapCount: Int {
        taps.count
    }
    
    private func makeReference(_ url: URL) throws -> AudioReference {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: url)
        return AudioReference(
            bookmark: try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
            lastKnownPath: url.path,
            fileName: url.lastPathComponent,
            duration: Double(file.length) / file.processingFormat.sampleRate,
            sampleRate: file.processingFormat.sampleRate,
            channelCount: Int(file.processingFormat.channelCount),
            fingerprint: try AudioFingerprint.of(url))
    }
    
    /// Finds and decodes the sequence's audio in the background, then renders it.
    private func loadAudio() {
        unloadAudio()
        guard let reference = sequence?.audio?.reference else { return }
        
        var isStale = false
        guard let bookmark = reference.bookmark,
              let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() || FileManager.default.isReadableFile(atPath: url.path),
              FileManager.default.fileExists(atPath: url.path) else {
            audioStatus = .missing
            return
        }
        audioURL = url
        audioStatus = .loading
        
        let owner = WeakSession(self)
        Task.detached(priority: .userInitiated) {
            do {
                let audio = try AudioData.load(url)
                let peaks = WaveformPeaks(audio)
                await MainActor.run {
                    guard let session = owner.session, session.audioURL == url else { return }
                    session.sourceAudio = audio
                    session.peaks = peaks
                    session.audioStatus = .ready
                    session.scheduleRender(delay: 0)
                    session.analyseAudio()
                }
            } catch {
                let message = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
                await MainActor.run {
                    guard let session = owner.session, session.audioURL == url else { return }
                    session.audioStatus = .failed(message)
                }
            }
        }
    }
    
    private func unloadAudio() {
        renderTask?.cancel()
        analysisTask?.cancel()
        analysis = nil
        analysisProgress = nil
        renderDelay?.cancel()
        audioURL?.stopAccessingSecurityScopedResource()
        audioURL = nil
        sourceAudio = nil
        peaks = nil
        rendered = nil
        renderProgress = nil
        if sequence?.audio == nil {
            audioStatus = .none
        }
    }
    
    /// Re-renders the warped audio shortly after the last change, cancelling any render in progress.
    private func scheduleRender(delay: Double = 0.4) {
        renderDelay?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.render() }
        renderDelay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    private func render() {
        renderTask?.cancel()
        guard let source = sourceAudio, let sequence, let audio = sequence.audio else { return }
        let map = audio.map(tempo: sequence.tempo)
        let tempo = sequence.tempo
        let beats = sequence.lengthInBeats
        renderProgress = 0
        
        let owner = WeakSession(self)
        renderTask = Task.detached(priority: .userInitiated) {
            var lastReport = Date.distantPast
            let result = WarpRenderer.render(source, map: map, tempo: tempo, beats: beats) { progress in
                if Task.isCancelled { return false }
                if Date().timeIntervalSince(lastReport) > 0.1 {
                    lastReport = Date()
                    Task { @MainActor in owner.session?.renderProgress = progress }
                }
                return true
            }
            guard !Task.isCancelled, let result else { return }
            await MainActor.run {
                owner.session?.finishRender(result)
            }
        }
    }
    
    // MARK: - Analysis
    
    /// Listens for tempo, beats, bar 1, chords and key in the background.
    func analyseAudio() {
        analysisTask?.cancel()
        guard let source = sourceAudio, let beatsPerBar = sequence?.beatsPerBar else { return }
        analysisProgress = 0
        showsAnalysis = true
        
        let owner = WeakSession(self)
        analysisTask = Task.detached(priority: .utility) {
            var lastReport = Date.distantPast
            let result = AudioAnalysis.analyse(source, beatsPerBar: beatsPerBar) { progress in
                if Task.isCancelled { return false }
                if Date().timeIntervalSince(lastReport) > 0.1 {
                    lastReport = Date()
                    Task { @MainActor in owner.session?.analysisProgress = progress }
                }
                return true
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                owner.session?.analysis = result
                owner.session?.analysisProgress = nil
            }
        }
    }
    
    /// Re-tracks the beats at another tempo, e.g. half or double what was first heard.
    func useAnalysedTempo(_ bpm: Double) {
        analysis?.track(tempo: bpm)
    }
    
    /// Moves the guessed bar 1 by a beat or more.
    func shiftAnalysedBarOne(by beats: Int) {
        analysis?.shiftDownbeat(by: beats)
    }
    
    /// Sets the tempo from the recording and puts a warp marker on every downbeat, so the grid follows the band.
    func applyAnalysedBeatGrid() {
        guard let analysis, var sequence else { return }
        sequence.tempo = (analysis.tempo * 10).rounded() / 10
        sequence.audio?.removeAllMarkers()
        for marker in analysis.warpMarkers {
            sequence.audio?.setMarker(marker)
        }
        sequence.setLength(bars: analysis.lengthInBars)
        self.sequence = sequence
    }
    
    /// Puts the heard chords on the grid: everywhere, or only where there's no chord yet.
    func applyAnalysedChords(onlyEmpty: Bool) {
        // Chords are placed by the heard beats, so the grid has to follow them first
        if sequence?.audio?.warpMarkers.isEmpty == true {
            applyAnalysedBeatGrid()
        }
        guard let analysis, var sequence else { return }
        if !onlyEmpty {
            sequence.clearChords(in: BeatRange(0, sequence.lengthInBeats))
        }
        for region in analysis.chordRegions(key: sequence.key ?? analysis.key) {
            if onlyEmpty && sequence.chords.contains(where: { $0.range.overlaps(region.range) }) {
                continue
            }
            sequence.setChord(region.symbol, in: region.range)
        }
        self.sequence = sequence
    }
    
    func applyAnalysedKey() {
        sequence?.key = analysis?.key
    }
    
    private func finishRender(_ result: RenderedAudio) {
        rendered = result
        renderProgress = nil
        if isPlaying, let sequence, let editor {
            playback.update(playbackData(sequence, editor: editor), id: editor.id)
        }
    }
}

/// Lets background work find the session again without keeping it alive.
private final class WeakSession: @unchecked Sendable {
    weak var session: SequenceSession?
    
    init(_ session: SequenceSession) {
        self.session = session
    }
}
