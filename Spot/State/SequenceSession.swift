//
//  SequenceSession.swift
//  Spot
//

import Foundation
import Observation
import AVFoundation
import UniformTypeIdentifiers
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
        didSet {
            // The menu bar's summary, set only when it changes (reading `sequence` itself, the menu bar would be
            // rebuilt for every edit and drag)
            if isOpen != (sequence != nil) { isOpen = sequence != nil }
            if isLooping != (sequence?.isLooping ?? false) { isLooping = sequence?.isLooping ?? false }
            if barLength != (sequence?.barLength ?? 4) { barLength = sequence?.barLength ?? 4 }
            sequenceChanged(from: oldValue)
        }
    }
    /// Whether a sequence is open (for the menu bar).
    private(set) var isOpen = false
    /// Whether it's looping (for the menu bar).
    private(set) var isLooping = false
    /// Its bar, in beats (for the menu bar).
    private(set) var barLength: Double = 4
    private(set) var editor: SequenceEditorState?
    private(set) var fileURL: URL?
    private(set) var hasUnsavedChanges = false
    private(set) var saveError: String?
    private(set) var recents: [Recent] = []
    
    private(set) var audioStatus: AudioStatus = .none
    /// Set when a relinked file isn't the recording the sequence was made with.
    private(set) var audioWarning: String?
    private(set) var peaks: WaveformPeaks?
    /// When the recording is a video file: its picture, following playback, and its frames.
    private(set) var video: VideoPlayback?
    /// The audio lined up with the grid, ready to play; nil until the first render is done.
    private(set) var rendered: RenderedAudio?

    /// The recording is still being read or lined up for the first time, so Play wouldn't be heard with it
    /// yet. (Not while re-rendering after an edit: the previous version plays until the new one's ready.
    /// Not if the file is missing or unreadable either: then the editor shows why.)
    var isPreparingAudio: Bool {
        guard sequence?.audio != nil else { return false }
        return audioStatus == .loading || (audioStatus == .ready && rendered == nil)
    }

    /// How far getting the recording ready has got, 0–1: reading it (to 0.35), then lining it up with the grid.
    private(set) var audioProgress: Double = 0

    private(set) var isRecording = false
    @ObservationIgnored private var recorder: InputRecorder?
    @ObservationIgnored private var recordingFile: (url: URL, name: String, tempo: Double)?
    
    /// The decoded recording (read by the waveform when zoomed in to single samples).
    @ObservationIgnored private(set) var sourceAudio: AudioData?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderDelay: DispatchWorkItem?
    /// What still needs re-rendering: everything, or just a stretch between warp markers.
    @ObservationIgnored private var pendingFullRender = false
    @ObservationIgnored private var pendingRenderRange: BeatRange?
    /// What the render in progress is doing, put back into `pending…` if it gets cancelled.
    @ObservationIgnored private var inFlight: (full: Bool, range: BeatRange?)?
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

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    /// True when closing would lose work: an unsaved sequence with something in it.
    var needsSaveBeforeClosing: Bool {
        guard let sequence, fileURL == nil else { return false }
        return !sequence.chords.isEmpty || !sequence.instances.isEmpty
    }

    var isPlaying: Bool {
        editor.map { playback.playingSequence == $0.id } ?? false
    }

    // MARK: - Undo

    /// Whether Undo and Redo have anything to do.
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// The sequence before each change, most recent last.
    @ObservationIgnored private var undoStack: [ChordSequence] = []
    @ObservationIgnored private var redoStack: [ChordSequence] = []
    @ObservationIgnored private var lastChange = Date.distantPast
    @ObservationIgnored private var isUndoing = false

    /// Keeps the sequence from before a change. Changes in quick succession (dragging a slider or a
    /// number) are one step. Takes aren't undone: they're files, recorded or deleted for good.
    private func recordUndo(from old: ChordSequence?, to new: ChordSequence) {
        guard !isUndoing, var old else { return }
        old.takes = new.takes
        guard old != new else { return }
        if Date().timeIntervalSince(lastChange) > 0.5 || undoStack.isEmpty {
            undoStack.append(old)
            if undoStack.count > 200 {
                undoStack.removeFirst()
            }
        }
        lastChange = Date()
        redoStack.removeAll()
        updateUndoState()
    }

    func undo() {
        guard let current = sequence, let target = undoStack.popLast() else { return }
        redoStack.append(current)
        restore(target, from: current)
    }

    func redo() {
        guard let current = sequence, let target = redoStack.popLast() else { return }
        undoStack.append(current)
        restore(target, from: current)
    }

    private func restore(_ target: ChordSequence, from current: ChordSequence) {
        var target = target
        target.takes = current.takes
        // A different recording (undoing Replace Audio, say) has to be loaded again
        let audioChanged = target.audio?.reference != current.audio?.reference
        if audioChanged {
            unloadAudio()
        }
        // The tab has its own undo, in the tab editor
        target.tablature = current.tablature
        isUndoing = true
        sequence = target
        isUndoing = false

        if audioChanged {
            loadAudio()
        }
        lastChange = .distantPast
        updateUndoState()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func clearUndo() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastChange = .distantPast
        updateUndoState()
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
        clearUndo()
        defaults.removeObject(forKey: SequenceSession.lastFileKey)
        defaults.removeObject(forKey: SequenceSession.draftKey)
        onClose?()
    }

    private func load(_ sequence: ChordSequence, from url: URL?) {
        let editor = SequenceEditorState(library: library)
        editor.analyse(sequence)
        // Open at the start marker, with the playhead on it
        editor.select(BeatRange(sequence.startBeat, sequence.startBeat), extend: false, in: sequence)
        editor.revealOnLayout = sequence.startBeat
        self.editor = editor
        fileURL = url
        isLoading = true
        self.sequence = sequence
        isLoading = false
        hasUnsavedChanges = false
        saveError = nil
        clearUndo()
        loadAudio()
        onOpen?()
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

    /// What Save As writes, including any recorded takes.
    var document: SequenceDocument? {
        guard let sequence else { return nil }
        var extras: [String: FileWrapper] = [:]
        if let folder = takesFolder, let takes = try? FileWrapper(url: folder) {
            extras["takes"] = takes
        }
        return SequenceDocument(sequence: sequence, extraFiles: extras)
    }
    
    // MARK: - Recording
    
    /// Where takes are saved: inside the `.spot` package (so the sequence needs a file first).
    var takesFolder: URL? {
        fileURL?.appendingPathComponent("takes", isDirectory: true)
    }
    
    /// Starts recording a new take, and starts playback (with the count-in) if it isn't playing.
    func startRecording() throws {
        guard !isRecording, let folder = takesFolder, let sequence else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        var number = sequence.takes.count + 1
        var url = folder.appendingPathComponent("Take \(number).caf")
        while FileManager.default.fileExists(atPath: url.path) {
            number += 1
            url = folder.appendingPathComponent("Take \(number).caf")
        }
        
        let recorder = self.recorder ?? InputRecorder()
        self.recorder = recorder
        try recorder.setDevice(playback.settings.inputDeviceID)
        try recorder.start(writingTo: url)
        recordingFile = (url, "Take \(number)", sequence.tempo)
        isRecording = true
        if !isPlaying {
            play()
        }
    }
    
    /// Finishes the take and puts it on the grid where its first sound was heard.
    func stopRecording() {
        guard isRecording, let recorder, let file = recordingFile else { return }
        isRecording = false
        recordingFile = nil
        guard let result = recorder.stop() else {
            try? FileManager.default.removeItem(at: file.url)
            return
        }
        // The first sample was captured `latency` after it was played
        let latency = recorder.inputLatency + playback.settings.recordingOffsetMs / 1000
        let soundedAt = HostTime.adding(-latency, to: result.startHostTime)
        let startBeat = transport.isPlaying ? transport.position(at: soundedAt) : (editor?.selection.start ?? 0)
        sequence?.takes.append(RecordedTake(name: file.name, fileName: file.url.lastPathComponent, startBeat: startBeat,
                                            duration: result.duration, tempo: file.tempo))
    }
    
    func removeTake(_ id: UUID) {
        guard let take = sequence?.takes.first(where: { $0.id == id }) else { return }
        sequence?.takes.removeAll { $0.id == id }
        if let folder = takesFolder {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(take.fileName))
        }
    }
    
    func setTakeMuted(_ id: UUID, _ muted: Bool) {
        guard let index = sequence?.takes.firstIndex(where: { $0.id == id }) else { return }
        sequence?.takes[index].isMuted = muted
    }

    /// The sequence before a change, while the length is being fitted to it.
    @ObservationIgnored private var fittingFrom: ChordSequence??

    /// Where the rendered audio stops: the end of the bar the recording ends in.
    private static func renderEnd(_ sequence: ChordSequence) -> Double? {
        guard let end = sequence.audioEndBeat else { return nil }
        let bar = sequence.barLength
        return min(sequence.lengthInBeats, ceil(end / bar - 1e-9) * bar)
    }

    private func sequenceChanged(from old: ChordSequence?) {
        guard !isLoading, var fitted = sequence, fitted != old else { return }
        if let old, old.timeSignature != fitted.timeSignature {
            let change = (old.timeSignature, fitted.timeSignature)
            // After this change has settled (the tab's edit comes back into the sequence)
            DispatchQueue.main.async { [weak self] in self?.onTimeSignatureChange?(change.0, change.1) }
        }
        // The length follows the content (plus a few spare bars). Fitting sets the sequence again, which
        // comes back here; that pass does the work, measured against the sequence from before both.
        fitted.fitLength()
        if fitted != sequence {
            fittingFrom = .some(old)
            self.sequence = fitted
            return
        }
        let old = fittingFrom ?? old
        fittingFrom = nil
        guard let sequence else { return }
        // A tab edit is an undo step in the tab editor, and changes nothing the analysis looks at
        if !isTabEdit {
            recordUndo(from: old, to: sequence)
            // The analysis (every chord's scale and shapes) is slow and only looks at the chords and key: not
            // re-done for a warp marker, the loop, the markers…
            if old?.chords != sequence.chords || old?.key != sequence.key {
                editor?.analyse(sequence)
            }
        }
        
        // The rendered audio depends on the markers and the recording's tempo (not the sequence's: that's
        // applied as it plays), and runs to the end of the recording.
        // Moving one marker only changes the audio between its neighbours, so just that stretch is
        // re-rendered (quickly).
        if sequence.audio?.tempo != old?.audio?.tempo || SequenceSession.renderEnd(sequence) != old.flatMap(SequenceSession.renderEnd) {
            scheduleRender()
        } else if let markers = sequence.audio?.warpMarkers, markers != old?.audio?.warpMarkers {
            if let range = SequenceSession.affectedRange(old: old?.audio?.warpMarkers ?? [], new: markers) {
                scheduleRender(range: range, delay: 0.02)
            } else {
                scheduleRender(delay: 0.05)
            }
        }
        if isPlaying, let editor {
            playback.update(playbackData(sequence, editor: editor), id: editor.id)
            applyTempo(sequence)
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

    /// Play, or pause where it is.
    func togglePlay() {
        isPlaying ? stopPlayback() : play()
    }
    
    /// Plays from the start marker (1.1.1), with a count-in, and carries on to the end marker.
    func play() {
        guard let sequence, let editor, !isPlaying, !isPreparingAudio else { return }
        playRangeEnd = nil
        start(sequence, editor: editor, from: sequence.startBeat, countIn: true)
    }

    /// Plays from the playhead (⌥Space); with a range selected, just that range, stopping at its end.
    /// While playing it doesn't stop: it jumps back to the playhead and carries on from there.
    func playSelection() {
        guard let sequence, let editor, !isPreparingAudio else { return }
        let selection = editor.selection
        playRangeEnd = selection.length > 0 ? selection.end : nil
        if isPlaying {
            guard !isRecording else { return }
            start(sequence, editor: editor, from: selection.start, countIn: false)
        } else {
            start(sequence, editor: editor, from: selection.start, countIn: true)
        }
    }

    /// Where playback stops when playing just the selection.
    @ObservationIgnored private var playRangeEnd: Double?

    /// Where the current playback started (before that, it's still counting in).
    @ObservationIgnored private var playedFrom: Double = 0

    private func start(_ sequence: ChordSequence, editor: SequenceEditorState, from beat: Double, countIn: Bool) {
        playedFrom = beat
        applyTempo(sequence)
        transport.timeSignature = sequence.timeSignature
        editor.followSuspended = false
        playback.play(playbackData(sequence, editor: editor), from: beat, id: editor.id, countIn: countIn)
        // Again once it's playing, for the practice speed (starting stops whatever was playing, which puts the
        // clock back to the tempo)
        applyTempo(sequence)
    }
    
    /// The clock runs at the sequence's tempo (times the practice speed, while playing), and the recording is sped
    /// up or slowed down from its own to match.
    private func applyTempo(_ sequence: ChordSequence) {
        let speed = isPlaying ? playback.practiceSpeed : 1
        transport.setBPM(sequence.tempo * speed)
        transport.barOrigin = sequence.startBeat
        playback.setAudioRate(sequence.audio.map { sequence.tempo * speed / $0.tempo } ?? speed)
    }

    /// ⌘L and the Loop button. With a range selected: loop it (or, if it's already the loop, stop looping).
    /// With just a playhead: turn looping off, or back on over the loop brace (the first time, the bar the
    /// playhead is in).
    func toggleLoop() {
        guard let editor, let sequence else { return }
        let selection = editor.selection
        if selection.length > 0 {
            self.sequence?.loop = sequence.loop == selection ? nil : selection
        } else if sequence.isLooping {
            self.sequence?.loop = nil
        } else if sequence.loopRange != nil {
            self.sequence?.isLooping = true
        } else {
            let bar = sequence.barLength
            let start = sequence.onGrid(selection.start, unit: bar)
            self.sequence?.loop = BeatRange(start, min(start + bar, sequence.lengthInBeats))
        }
    }

    /// Steps the voicing of the chord at the playhead along its options (up or down the neck), picking it.
    func cycleVoicing(by step: Int) {
        guard let editor, let sequence, let region = sequence.chord(at: editor.selection.start),
              let chord = editor.analysis.chords[region.id] else { return }
        let options = editor.voicingOptions(for: chord)
        guard !options.isEmpty else { return }
        let current = editor.analysis.positions[region.id]?.voicing.flatMap { voicing in
            options.firstIndex { $0.pick == voicing.pick }
        }
        let next = ((current ?? (step > 0 ? -1 : 0)) + step + options.count) % options.count
        self.sequence?.pick(region.id, voicing: .some(options[next].pick))
    }

    /// Moves playback to `beat` while playing (clicking in the lane), without a count-in.
    func seek(to beat: Double) {
        guard isPlaying, !isRecording, let sequence, let editor else { return }
        playRangeEnd = nil
        playedFrom = beat
        playback.play(playbackData(sequence, editor: editor), from: beat, id: editor.id, countIn: false)
        applyTempo(sequence)
    }

    /// Stops. Play starts from 1.1.1 again (⌥Space from the playhead).
    /// Stopping by hand leaves the playhead where playback got to (unless it was still counting in).
    func stopPlayback() {
        stopRecording()
        playRangeEnd = nil
        if isPlaying {
            let position = transport.position()
            playback.stop()
            if let editor, let sequence, position >= playedFrom {
                let beat = min(max(0, position), sequence.lengthInBeats)
                editor.select(BeatRange(beat, beat), extend: false, in: sequence)
            }
        }
    }
    
    /// Back to bar 1.
    /// Back to 1.1.1 (the start marker).
    func returnToStart() {
        let wasPlaying = isPlaying
        stopPlayback()
        if let sequence {
            editor?.select(BeatRange(sequence.startBeat, sequence.startBeat), extend: false, in: sequence)
        }
        if wasPlaying {
            play()
        }
    }
    
    private func playbackData(_ sequence: ChordSequence, editor: SequenceEditorState) -> SequencePlayback {
        var data = editor.playback(for: sequence)
        // Playing just the selection: stop at its end, not looping
        if let end = playRangeEnd {
            data.length = min(data.length, end)
            data.loop = nil
        } else if !isRecording {
            // Stop at the end marker, or the end of the bar the content ends in, not after the spare bars
            // (unless recording into them). A tab playing along counts as content.
            data.length = min(sequence.lengthInBeats, sequence.songEnd)
        }
        if let audio = sequence.audio, !audio.isMuted, rendered?.tempo == audio.tempo {
            data.audio = rendered
            data.audioGain = Float(pow(10, audio.gain / 20))
        }
        if let tablature = sequence.tablature, !sequence.tabIsMuted {
            data.tab = tabPerformance(tablature)
            data.tabStart = sequence.startBeat
        }
        if let folder = takesFolder {
            data.takes = sequence.takes.filter { !$0.isMuted }.map { take in
                TakePlayback(id: take.id, url: folder.appendingPathComponent(take.fileName), startBeat: take.startBeat,
                             tempo: take.tempo, volume: Float(pow(10, take.gain / 20)))
            }
        }
        return data
    }
    
    // MARK: - Patterns

    /// The pattern at the playhead (or the selection's start).
    var selectedPattern: (instance: PatternInstance, pattern: ChordPattern)? {
        guard let sequence, let editor else { return nil }
        return sequence.patternInstance(at: editor.selection.start)
    }

    /// Whether ⌘G can group the selection: a range, not over a pattern.
    var canGroupSelection: Bool {
        guard let sequence, let editor, editor.selection.length > 0 else { return false }
        return !sequence.instances.contains { $0.range.overlaps(editor.selection) }
    }

    /// ⌘G: the selected stretch becomes a pattern, selected.
    func groupSelection() {
        guard canGroupSelection, let editor, var sequence else { return }
        let range = editor.selection
        guard sequence.makePattern(from: range) != nil else { return }
        self.sequence = sequence
        editor.select(range, extend: false, in: sequence)
    }

    /// ⇧⌘G: the pattern at the playhead back to plain chords.
    func ungroupPattern() {
        guard let instance = selectedPattern?.instance else { return }
        sequence?.ungroup(instance.id)
    }

    /// ⌘D: the pattern again straight after itself (linked), selected.
    func duplicatePattern() {
        guard let instance = selectedPattern?.instance, let editor, var sequence else { return }
        guard let copy = sequence.duplicate(instance.id) else { return }
        self.sequence = sequence
        if let placed = sequence.instances.first(where: { $0.id == copy }) {
            editor.select(placed.range, extend: false, in: sequence)
        }
    }

    /// The pattern at the playhead out of the sequence, chords and all.
    func deletePattern() {
        guard let instance = selectedPattern?.instance, let editor, var sequence else { return }
        sequence.removeInstance(instance.id)
        self.sequence = sequence
        editor.select(BeatRange(instance.range.start, instance.range.start), extend: false, in: sequence)
    }

    /// Delete: clears the selection's chords; patterns wholly in it go.
    func deleteSelection() {
        guard let editor, editor.selection.length > 0 else { return }
        sequence?.clearChords(in: editor.selection)
    }

    func makePatternUnique() {
        guard let instance = selectedPattern?.instance else { return }
        sequence?.makeUnique(instance.id)
    }

    func renamePattern(_ id: UUID, to name: String) {
        sequence?.rename(pattern: id, to: name)
    }

    // MARK: - The tab

    /// Told when a sequence opens or closes, for the tab editor to show its tab (or not).
    @ObservationIgnored var onOpen: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    /// Told when the time signature changes (old and new), for the tab to follow.
    @ObservationIgnored var onTimeSignatureChange: ((TimeSignature, TimeSignature) -> Void)?
    /// Set while the tab editor puts in an edit (which isn't an undo step here: the tab editor has its own undo).
    @ObservationIgnored private var isTabEdit = false
    @ObservationIgnored private var cachedTabPerformance: (score: TabScore, performance: TabPerformance)?

    /// The tab editor changed the tab.
    func setTablature(_ score: TabScore) {
        guard sequence != nil, sequence?.tablature != score else { return }
        isTabEdit = true
        sequence?.tablature = score
        isTabEdit = false
    }

    /// Puts the playhead on a beat (from the tab editor's cursor), when not playing.
    func movePlayhead(to beat: Double) {
        guard !isPlaying, let sequence, let editor else { return }
        let beat = min(max(beat, 0), sequence.lengthInBeats)
        guard editor.selection != BeatRange(beat, beat) else { return }
        editor.select(BeatRange(beat, beat), extend: false, in: sequence)
    }

    /// Loops a range (from the tab editor's selection), or with nil turns looping on or off.
    func loop(_ range: BeatRange?) {
        guard let range, range.length > 0 else { return toggleLoop() }
        sequence?.loop = sequence?.loop == range ? nil : range
    }

    /// A tab for this sequence: one guitar track, in its time signature, from the start marker to its end.
    func blankTablature() -> TabScore {
        guard let sequence else { return TabScore.empty() }
        let bars = max(1, Int(ceil((sequence.lengthInBeats - sequence.startBeat) / sequence.barLength - 1e-9)))
        var score = TabScore.empty(bars: bars)
        for index in score.masterBars.indices {
            score.masterBars[index].timeSignature = sequence.timeSignature
        }
        score.tempo = sequence.tempo
        return score
    }

    /// The tab timed in beats (its quarter notes), for playing along.
    private func tabPerformance(_ score: TabScore) -> TabPerformance {
        if let cached = cachedTabPerformance, cached.score == score { return cached.performance }
        let performance = TabPerformance.make(score, inQuarterNotes: true)
        cachedTabPerformance = (score, performance)
        return performance
    }

    /// The track whose chord names are used: the first with any.
    private func chordTrack(in score: TabScore) -> Int {
        score.tracks.indices.first { !score.chordChanges(track: $0).isEmpty } ?? 0
    }

    /// Whether the tab has chord names to bring into the sequence.
    var tablatureHasChords: Bool {
        guard let score = sequence?.tablature else { return false }
        return score.tracks.indices.contains { !score.chordChanges(track: $0).isEmpty }
    }

    /// Puts the tab's chord names into the sequence where they come as it plays (lengthening the sequence if the
    /// tab runs past its end), replacing the chords there. One undo. Returns the names Spot couldn't read as chords.
    @discardableResult
    func addChordsFromTablature() -> [String] {
        guard var sequence, let score = sequence.tablature else { return [] }
        let changes = score.chordChanges(track: chordTrack(in: score))
        guard let last = changes.last else { return [] }
        let start = sequence.startBeat
        let end = start + last.range.end
        if end > sequence.lengthInBeats {
            sequence.setLength(bars: Int(ceil(end / sequence.barLength - 1e-9)))
        }
        let parser = ChordSymbolParser(chords: library.chords)
        var unreadable: [String] = []
        for change in changes {
            guard parser.parse(change.name) != nil else {
                if !unreadable.contains(change.name) { unreadable.append(change.name) }
                continue
            }
            sequence.setChord(change.name, in: BeatRange(start + change.range.start, start + change.range.end))
        }
        self.sequence = sequence
        return unreadable
    }

    // MARK: - Audio
    
    /// Links a recording to the sequence (it stays where it is) and lengthens the sequence to fit it.
    func importAudio(_ url: URL) throws {
        let reference = try makeReference(url)
        let secondsPerBar = (sequence?.barLength ?? 4) * 60 / (sequence?.tempo ?? 120)
        // Starts at bar 1, at the sequence's tempo until told otherwise
        sequence?.audio = AudioTrack(reference: reference, tempo: sequence?.tempo ?? 120)
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
    /// Tap along with the beat: after four taps, returns the tempo tapped (and keeps refining it with more).
    func tap() -> Double? {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2 {
            taps.removeAll()
        }
        taps.append(now)
        taps = Array(taps.suffix(9))
        guard taps.count >= 4 else { return nil }
        let interval = taps.last!.timeIntervalSince(taps.first!) / Double(taps.count - 1)
        return min(max((60 / interval * 10).rounded() / 10, 20), 300)
    }

    /// Tap tempo for the sequence: the tempo it plays at.
    func tapTempo() {
        guard let tapped = tap() else { return }
        sequence?.tempo = tapped
        if !isPlaying {
            transport.setBPM(tapped)
        }
    }

    /// Tap along with the recording to set its own tempo where the playhead is. While it's playing
    /// sped up or slowed down, the taps are scaled back to what it was played at.
    func tapRecordingTempo(atBeat beat: Double) {
        guard let tapped = tap(), let sequence, let audio = sequence.audio else { return }
        let heardRate = isPlaying ? sequence.tempo / audio.tempo : 1
        self.sequence?.audio?.setSegmentTempo((tapped / heardRate * 10).rounded() / 10, atBeat: beat)
    }

    private func makeReference(_ url: URL) throws -> AudioReference {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        // A video file: its soundtrack is the recording
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true || (try? AVAudioFile(forReading: url)) == nil {
            let media = try MediaInfo(url)
            return AudioReference(bookmark: bookmark, lastKnownPath: url.path, fileName: url.lastPathComponent,
                                  duration: media.duration, sampleRate: media.sampleRate, channelCount: media.channelCount,
                                  fingerprint: try AudioFingerprint.of(url), hasVideo: media.hasVideo)
        }
        let file = try AVAudioFile(forReading: url)
        return AudioReference(
            bookmark: bookmark,
            lastKnownPath: url.path,
            fileName: url.lastPathComponent,
            duration: Double(file.length) / file.processingFormat.sampleRate,
            sampleRate: file.processingFormat.sampleRate,
            channelCount: Int(file.processingFormat.channelCount),
            fingerprint: try AudioFingerprint.of(url))
    }

    /// Where the video should be: the moment in the recording at the playhead (playing, and how fast it's going
    /// there, through the warp markers and at the sequence's tempo).
    private func videoTarget() -> (time: Double, speed: Double)? {
        guard let sequence, let audio = sequence.audio, let editor else { return nil }
        let map = audio.map
        guard isPlaying else {
            return (map.sourceTime(atBeat: editor.playhead), 0)
        }
        let beat = transport.position()
        let time = map.sourceTime(atBeat: beat)
        let ahead = map.sourceTime(atBeat: beat + 0.05)
        return (time, max(0, (ahead - time) / 0.05 * transport.bpm / 60))
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
        audioProgress = 0.05
        if reference.hasVideo {
            let video = VideoPlayback(url: url, duration: reference.duration)
            video.target = { [weak self] in self?.videoTarget() }
            self.video = video
        }
        
        let owner = WeakSession(self)
        Task.detached(priority: .userInitiated) {
            do {
                let audio = try await AudioData.loadMedia(url)
                let peaks = WaveformPeaks(audio)
                await MainActor.run {
                    guard let session = owner.session, session.audioURL == url else { return }
                    session.sourceAudio = audio
                    session.peaks = peaks
                    session.audioProgress = 0.35
                    session.audioStatus = .ready
                    session.scheduleRender(delay: 0)
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
        inFlight = nil
        pendingFullRender = false
        pendingRenderRange = nil
        renderDelay?.cancel()
        video?.close()
        video = nil
        audioURL?.stopAccessingSecurityScopedResource()
        audioURL = nil
        sourceAudio = nil
        peaks = nil
        rendered = nil
        if sequence?.audio == nil {
            audioStatus = .none
        }
    }
    
    /// The beats whose audio changes when warp markers go from `old` to `new`; nil if it could be anywhere
    /// (an outer marker moved, so the stretch beyond it changes too, or there are fewer than two markers).
    static func affectedRange(old: [WarpMarker], new: [WarpMarker]) -> BeatRange? {
        let changed = Set(old).symmetricDifference(Set(new))
        guard !changed.isEmpty else { return BeatRange(0, 0) }
        guard old.count >= 2, new.count >= 2 else { return nil }
        var low = Double.infinity, high = -Double.infinity
        for markers in [old, new] {
            let sorted = markers.sorted { $0.beat < $1.beat }
            for (index, marker) in sorted.enumerated() where changed.contains(marker) {
                guard index > 0, index < sorted.count - 1 else { return nil }
                low = min(low, sorted[index - 1].beat)
                high = max(high, sorted[index + 1].beat)
            }
        }
        return low <= high ? BeatRange(low, high) : nil
    }
    
    /// Re-renders the warped audio shortly after the last change: all of it, or only `range`.
    private func scheduleRender(range: BeatRange? = nil, delay: Double = 0.4) {
        if let range {
            pendingRenderRange = pendingRenderRange.map { BeatRange(min($0.start, range.start), max($0.end, range.end)) } ?? range
        } else {
            pendingFullRender = true
        }
        renderDelay?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.render() }
        renderDelay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    private func render() {
        // A render still running hasn't delivered; fold its work back in before replacing it
        if let inFlight {
            if inFlight.full { pendingFullRender = true }
            if let range = inFlight.range {
                pendingRenderRange = pendingRenderRange.map { BeatRange(min($0.start, range.start), max($0.end, range.end)) } ?? range
            }
        }
        renderTask?.cancel()
        guard let source = sourceAudio, let sequence, let audio = sequence.audio else { return }
        // Rendered at the recording's own tempo; playback speeds it up or slows it down to the sequence's
        let map = audio.map
        let tempo = audio.tempo
        let end = SequenceSession.renderEnd(sequence) ?? sequence.lengthInBeats
        // Include anything recorded before bar 1, so it can play during the count-in
        let start = min(0, floor(map.beat(atSourceTime: 0)))
        
        let canSplice = !pendingFullRender && pendingRenderRange != nil && rendered.map {
            $0.tempo == tempo && $0.startBeat == start && abs($0.endBeat - end) < 0.01
        } == true
        let job: (full: Bool, range: BeatRange?) = canSplice ? (false, pendingRenderRange) : (true, nil)
        pendingFullRender = false
        pendingRenderRange = nil
        inFlight = job
        
        let owner = WeakSession(self)
        if let range = job.range, let base = rendered {
            // Just the stretch that changed (with a little either side), spliced into the existing render
            let from = max(start, range.start - 0.5), to = min(end, range.end + 0.5)
            renderTask = Task.detached(priority: .userInitiated) {
                guard let segment = WarpRenderer.render(source, map: map, tempo: tempo, from: from, to: to,
                                                        progress: { _ in !Task.isCancelled }),
                      !Task.isCancelled else { return }
                var spliced = base
                spliced.splice(segment)
                let updated = spliced
                await MainActor.run { owner.session?.finishRender(updated) }
            }
            return
        }
        
        // Quiet: at the recording's own tempo this is mostly a copy, and only stretched sections take any time
        // The first render is what loading waits for: report how far it's got
        let reportsProgress = rendered == nil
        renderTask = Task.detached(priority: .userInitiated) {
            var reported = 0.0
            let result = WarpRenderer.render(source, map: map, tempo: tempo, from: start, to: end) { fraction in
                if reportsProgress, fraction - reported >= 0.02 {
                    reported = fraction
                    DispatchQueue.main.async { owner.session?.audioProgress = 0.35 + 0.65 * fraction }
                }
                return !Task.isCancelled
            }
            guard !Task.isCancelled else { return }
            // Nothing to render (e.g. the recording lies outside the sequence): silence, rather than
            // waiting for audio that will never come
            let rendered = result ?? RenderedAudio(audio: AudioData(channels: source.channels.map { _ in [] },
                                                                    sampleRate: source.sampleRate),
                                                   tempo: tempo, startBeat: start)
            await MainActor.run {
                owner.session?.finishRender(rendered)
            }
        }
    }
    
    private func finishRender(_ result: RenderedAudio) {
        inFlight = nil
        rendered = result
        audioProgress = 1
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
