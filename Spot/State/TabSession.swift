//
//  TabSession.swift
//  Spot
//

import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import SpotCore

extension UTType {
    /// A tab (tablature) file: JSON.
    static let spotTab = UTType(exportedAs: "iko.spot.tab", conformingTo: .json)

    /// Guitar Pro files, by extension (Guitar Pro declares the types, but it may not be installed).
    static let guitarProTypes: [UTType] = GuitarPro.fileExtensions.compactMap { UTType(filenameExtension: $0) }
    static let guitarPro7 = UTType(filenameExtension: "gp") ?? .data
}

/// The tab as a Guitar Pro 7 file, for exporting.
struct GuitarProDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.guitarPro7] }

    var data: Data

    init(score: TabScore) {
        data = GuitarPro.gp7(score)
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A tab as a document, for the Save panel.
struct TabDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.spotTab] }

    var score: TabScore

    init(score: TabScore) {
        self.score = score
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        score = try TabScore.decode(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try score.encoded())
    }
}

/// The tab open in the Tab tab (one at a time), with its file: New / Open / Recent / Save, saved a second after
/// each change once it has a file, and kept across launches while it's still Untitled. Like `SequenceSession`.
@Observable
final class TabSession {
    struct Recent: Codable, Hashable, Identifiable {
        var name: String
        var bookmark: Data
        var id: Data { bookmark }
    }

    /// nil when nothing is open.
    var score: TabScore? {
        didSet { scoreChanged(from: oldValue) }
    }
    /// Where you are in it: the track showing and the cursor.
    private(set) var editor: TabEditorState?
    private(set) var fileURL: URL?
    private(set) var hasUnsavedChanges = false
    private(set) var saveError: String?
    private(set) var recents: [Recent] = []

    @ObservationIgnored private var autosave: DispatchWorkItem?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let recentsKey = "tab.recents"
    private static let lastFileKey = "tab.lastFile"
    private static let draftKey = "tab.untitledDraft"

    let playback: PlaybackController
    let transport: TransportState

    init(playback: PlaybackController, transport: TransportState) {
        self.playback = playback
        self.transport = transport
        recents = defaults.data(forKey: TabSession.recentsKey).flatMap { try? JSONDecoder().decode([Recent].self, from: $0) } ?? []
        restore()
    }

    // MARK: - Tempo and time signature (for the footer)

    /// The tempo at the cursor's bar: the last tempo change at or before it, or the tab's own tempo.
    /// Setting it changes that tempo change (or the tab's tempo if there's none).
    var tempoAtCursor: Double? {
        get {
            guard let score, let editor else { return nil }
            let change = score.masterBars.prefix(editor.cursor.bar + 1).last { $0.tempo != nil }?.tempo
            return change ?? score.tempo
        }
        set {
            guard let newValue, let score, let editor else { return }
            let tempo = min(max(newValue, 20), 300)
            if let bar = score.masterBars.prefix(editor.cursor.bar + 1).lastIndex(where: { $0.tempo != nil }) {
                self.score?.masterBars[bar].tempo = tempo
            } else {
                self.score?.tempo = tempo
            }
        }
    }

    var timeSignatureAtCursor: TimeSignature? {
        guard let score, let editor, score.masterBars.indices.contains(editor.cursor.bar) else { return nil }
        return score.masterBars[editor.cursor.bar].timeSignature
    }

    /// Sets the time signature from the cursor's bar on.
    func setTimeSignature(_ signature: TimeSignature) {
        guard let editor, timeSignatureAtCursor != signature else { return }
        score?.setTimeSignature(signature, from: editor.cursor.bar)
    }

    // MARK: - Playing

    /// Where playback is (the beat playing on the track showing); nil when not playing.
    private(set) var playhead: TabPosition?
    @ObservationIgnored private var performance: TabPerformance?
    @ObservationIgnored private var follower: Timer?

    var isPlaying: Bool {
        if let sequence = linkedSequence { return sequence.isPlaying }
        return playback.isPlayingTab
    }

    func togglePlay() {
        if let sequence = linkedSequence {
            sequence.togglePlay()
            return
        }
        isPlaying ? stopPlaying() : play(fromCursor: false)
    }

    /// From the start, or from the beat at the cursor. Plays the tab as it is now (edits made while playing are
    /// heard next time). Linked to the open sequence, it's the sequence that plays: from its start marker, or from
    /// the cursor's beat.
    func play(fromCursor: Bool) {
        if let sequence = linkedSequence {
            if fromCursor, let beat = cursorBeat {
                sequence.stopPlayback()
                sequence.movePlayhead(to: beat)
                sequence.playSelection()
            } else {
                sequence.stopPlayback()
                sequence.play()
            }
            return
        }
        guard let score, let editor else { return }
        let performance = TabPerformance.make(score)
        self.performance = performance
        let start = fromCursor ? performance.time(of: editor.position, track: editor.track) : 0
        transport.positionLabel = { time in
            performance.barAndBeat(at: time).map { "\($0.bar).\($0.beat)" } ?? ""
        }
        playback.play(tab: performance, from: start)
        follow()
    }

    func stopPlaying() {
        if let sequence = linkedSequence {
            sequence.stopPlayback()
            return
        }
        if isPlaying {
            playback.stop()
        }
        finishPlaying()
    }

    /// Back to the start (linked: the sequence's start marker), carrying on playing if it was.
    func returnToStart() {
        if let sequence = linkedSequence {
            sequence.returnToStart()
            if !sequence.isPlaying { syncCursorToSequence() }
            return
        }
        let wasPlaying = isPlaying
        stopPlaying()
        editor?.cursor = TabEditorState.Cursor()
        if wasPlaying { play(fromCursor: false) }
    }

    // MARK: - The sequence's tab

    /// Editing the open sequence's tab, rather than a .spottab file of its own. With a sequence open, the Tab tab
    /// always shows its tab, and the two share one transport.
    private(set) var isSequenceTab = false

    /// The sequence session, set by the app.
    @ObservationIgnored weak var sequenceSession: SequenceSession? {
        didSet {
            sequenceSession?.onOpen = { [weak self] in self?.attachToSequence() }
            sequenceSession?.onClose = { [weak self] in self?.detachFromSequence() }
            sequenceSession?.onTimeSignatureChange = { [weak self] old, new in self?.sequenceTimeSignatureChanged(from: old, to: new) }
            if sequenceSession?.sequence != nil { attachToSequence() }
        }
    }

    /// The sequence, when this is its tab.
    var linkedSequence: SequenceSession? {
        isSequenceTab ? sequenceSession : nil
    }

    /// Shows the open sequence's tab (a blank one in its time signature if it has none yet), padded with empty
    /// bars to the sequence's end. A .spottab that was open is saved (or kept as a draft) and comes back when the
    /// sequence closes.
    func attachToSequence() {
        guard let sequenceSession, let sequence = sequenceSession.sequence else { return }
        suspendStandalone()
        var score = sequence.tablature ?? sequenceSession.blankTablature()
        let needed = Int(ceil((sequence.lengthInBeats - sequence.startBeat) / sequence.barLength - 1e-9))
        while score.barCount < needed {
            score.insertBar()
        }
        load(score, from: nil)
        isSequenceTab = true
        // (Nothing goes back to the sequence until it's edited, so opening it doesn't count as a change)
    }

    /// The sequence's time signature changed: its tab's bars that were in the old one move to the new one (bars
    /// given a different one in the tab keep it), and it gets empty bars to reach the sequence's end if it needs
    /// them. An undo step in the tab editor.
    func sequenceTimeSignatureChanged(from old: TimeSignature, to new: TimeSignature) {
        guard isSequenceTab, var updated = score, let sequence = sequenceSession?.sequence else { return }
        for index in updated.masterBars.indices where updated.masterBars[index].timeSignature == old {
            updated.masterBars[index].timeSignature = new
        }
        let needed = Int(ceil((sequence.lengthInBeats - sequence.startBeat) / sequence.barLength - 1e-9))
        while updated.barCount < needed {
            updated.insertBar()
        }
        if updated != score {
            score = updated
        }
    }

    func detachFromSequence() {
        guard isSequenceTab else { return }
        stopFollowingSequence()
        clearState()
        isSequenceTab = false
        restore()
    }

    /// Puts a .spottab that's open aside: saved to its file, or (Untitled) kept as the draft.
    private func suspendStandalone() {
        if isSequenceTab {
            clearState()
            return
        }
        guard let score else { return }
        stopPlaying()
        if fileURL != nil, hasUnsavedChanges {
            try? save()
        } else if fileURL == nil, hasUnsavedChanges, let data = try? score.encoded() {
            defaults.set(data, forKey: TabSession.draftKey)
        }
        clearState()
    }

    /// The tab timed in beats, for lining it up with the sequence.
    @ObservationIgnored private var cachedBeatTiming: (score: TabScore, performance: TabPerformance)?
    private var beatTiming: TabPerformance? {
        guard let score else { return nil }
        if let cached = cachedBeatTiming, cached.score == score { return cached.performance }
        let performance = TabPerformance.make(score, inQuarterNotes: true)
        cachedBeatTiming = (score, performance)
        return performance
    }

    /// The sequence beat the cursor's beat plays on (the first time round).
    var cursorBeat: Double? {
        guard let editor, let sequence = linkedSequence?.sequence, let timing = beatTiming else { return nil }
        return sequence.startBeat + timing.time(of: editor.position, track: editor.track)
    }

    /// The beat playing on the track showing at a sequence beat.
    private func position(atSequenceBeat beat: Double) -> TabPosition? {
        guard let editor, let sequence = linkedSequence?.sequence, let timing = beatTiming,
              beat >= sequence.startBeat - 1e-9 else { return nil }
        return timing.position(of: editor.track, at: beat - sequence.startBeat).map { TabPosition(bar: $0.bar, beat: $0.beat) }
    }

    /// Exactly where a sequence beat falls in the tab: a bar and how far into it (in ticks), even in an empty bar.
    func place(atSequenceBeat beat: Double) -> (bar: Int, tick: Int)? {
        guard let sequence = linkedSequence?.sequence, let timing = beatTiming else { return nil }
        let time = beat - sequence.startBeat
        guard time >= -1e-9, let bar = timing.bars.last(where: { $0.time <= time + 1e-9 }) else { return nil }
        return (bar.bar, Int(((time - bar.time) * Double(TabDuration.ticksPerQuarter)).rounded()))
    }

    /// The sequence's chords, placed in the tab (for showing above it).
    var sequenceChords: [(bar: Int, tick: Int, name: String)] {
        guard let sequence = linkedSequence?.sequence else { return [] }
        return sequence.chords.compactMap { region in
            place(atSequenceBeat: region.range.start).map { ($0.bar, $0.tick, region.symbol) }
        }
    }

    /// The tempo to show at the start: the sequence's (the tab plays at it, not its own).
    var sequenceTempo: Double? {
        linkedSequence?.sequence?.tempo
    }

    /// Exactly where playback is in the tab (a line, so it shows in empty bars too); nil when not playing.
    private(set) var playheadPlace: (bar: Int, tick: Int)?

    /// The cursor moved: the sequence's playhead goes there too.
    func cursorMoved() {
        guard let sequence = linkedSequence, !sequence.isPlaying, let beat = cursorBeat else { return }
        sequence.movePlayhead(to: beat)
    }

    /// The cursor goes to where the sequence's playhead is (keeping its string).
    func syncCursorToSequence() {
        guard let sequence = linkedSequence, let editor, let beat = sequence.editor?.selection.start,
              let place = place(atSequenceBeat: beat) else { return }
        // The beat there, or (in an empty bar or past the last beat) the slot after the last one
        let position = position(atSequenceBeat: beat).flatMap { $0.bar == place.bar ? $0 : nil }
            ?? TabPosition(bar: place.bar, beat: place.tick == 0 ? 0 : (score?.beats(track: editor.track, bar: place.bar).count ?? 0))
        if editor.position != position {
            editor.cursor = TabEditorState.Cursor(bar: position.bar, beat: position.beat, string: editor.cursor.string)
            editor.selectionAnchor = nil
        }
    }

    /// The sequence's loop, as the beats it covers on the track showing (while looping).
    var loopSpan: (start: TabPosition, end: TabPosition)? {
        guard let sequence = linkedSequence?.sequence, let loop = sequence.loop,
              let start = position(atSequenceBeat: max(loop.start, sequence.startBeat)),
              let end = position(atSequenceBeat: loop.end - 0.01) else { return nil }
        return (start, end)
    }

    /// The selected beats as a range of sequence beats, to loop.
    var selectionBeats: BeatRange? {
        guard let editor, let selection = editor.selection, let score, let sequence = linkedSequence?.sequence,
              let timing = beatTiming else { return nil }
        let start = timing.time(of: selection.start, track: editor.track)
        let lastBeats = score.beats(track: editor.track, bar: selection.end.bar)
        let lastLength = lastBeats.indices.contains(selection.end.beat)
            ? Double(lastBeats[selection.end.beat].duration.ticks) / Double(TabDuration.ticksPerQuarter) : 0
        let end = timing.time(of: selection.end, track: editor.track) + lastLength
        return BeatRange(sequence.startBeat + start, sequence.startBeat + end)
    }

    /// While the Tab tab shows the sequence's tab: follow the sequence (the playing beat while it plays; the
    /// cursor to where it stopped).
    func followSequence() {
        sequenceFollower?.invalidate()
        var wasPlaying = linkedSequence?.isPlaying ?? false
        sequenceFollower = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let sequence = linkedSequence else { return }
            if sequence.isPlaying {
                let beat = transport.position()
                let place = place(atSequenceBeat: beat)
                // The beat playing, unless it's over (in a rest-less gap or an empty bar, just the line shows)
                let position = position(atSequenceBeat: beat).flatMap { position -> TabPosition? in
                    guard position.bar == place?.bar, let score = self.score, let editor = self.editor else { return nil }
                    let beats = score.beats(track: editor.track, bar: position.bar)
                    let ends = beats.prefix(position.beat + 1).reduce(0) { $0 + $1.duration.ticks }
                    return (place?.tick ?? 0) < ends ? position : nil
                }
                if position != playhead { playhead = position }
                if place?.bar != playheadPlace?.bar || place?.tick != playheadPlace?.tick { playheadPlace = place }
            } else {
                if playhead != nil { playhead = nil }
                if playheadPlace != nil { playheadPlace = nil }
                if wasPlaying { syncCursorToSequence() }
            }
            wasPlaying = sequence.isPlaying
        }
        syncCursorToSequence()
    }

    func stopFollowingSequence() {
        sequenceFollower?.invalidate()
        sequenceFollower = nil
    }

    @ObservationIgnored private var sequenceFollower: Timer?

    private func finishPlaying() {
        follower?.invalidate()
        follower = nil
        playhead = nil
        transport.positionLabel = nil
    }

    /// Keeps `playhead` on the beat being played (only changing when the beat does).
    private func follow() {
        follower?.invalidate()
        follower = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard playback.isPlayingTab, let performance, let editor else {
                finishPlaying()
                return
            }
            let moment = performance.position(of: editor.track, at: transport.position())
            let position = moment.map { TabPosition(bar: $0.bar, beat: $0.beat) }
            if position != playhead {
                playhead = position
            }
        }
    }

    var isOpen: Bool {
        score != nil
    }

    var displayName: String {
        if let sequence = linkedSequence { return sequence.displayName }
        return fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    /// An Untitled tab with something in it would be lost by opening another. (The sequence's tab is saved with it.)
    var needsSaveBeforeClosing: Bool {
        !isSequenceTab && fileURL == nil && hasUnsavedChanges
    }

    // MARK: - Opening and closing

    /// A new tab; for the sequence's tab, a blank one in its place (which can be undone).
    func newScore() {
        if let sequence = linkedSequence {
            score = sequence.blankTablature()
            return
        }
        close()
        load(TabScore.empty(), from: nil)
    }

    /// Tracks a Guitar Pro file had that couldn't be brought in (drums), to tell you about; nil once told.
    var skippedOnImport: [String]?

    /// Opens a .spottab or Guitar Pro file; with a sequence open, it becomes the sequence's tab (which can be undone).
    func open(_ url: URL) throws {
        if GuitarPro.fileExtensions.contains(url.pathExtension.lowercased()) {
            try importGuitarPro(url)
            return
        }
        if isSequenceTab {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            score = try TabScore.decode(from: Data(contentsOf: url))
            remember(url)
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let score = try TabScore.decode(from: Data(contentsOf: url))
            close()
            load(score, from: url)
            remember(url)
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Opens a Guitar Pro file as a new, Untitled tab (saving makes a `.spottab`; the original is left alone).
    func importGuitarPro(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let imported = try GuitarPro.read(Data(contentsOf: url))
        guard !imported.score.tracks.isEmpty else {
            throw GuitarPro.Error.unsupported("Guitar Pro files with only drum tracks")
        }
        var score = imported.score
        if score.title.isEmpty {
            score.title = url.deletingPathExtension().lastPathComponent
        }
        if isSequenceTab {
            self.score = score
            skippedOnImport = imported.skippedTracks.isEmpty ? nil : imported.skippedTracks
            return
        }
        close()
        load(score, from: nil)
        // Untitled with something in it: kept as a draft, and you're asked to save before it's replaced
        hasUnsavedChanges = true
        scheduleAutosave()
        skippedOnImport = imported.skippedTracks.isEmpty ? nil : imported.skippedTracks
    }

    var guitarProDocument: GuitarProDocument? {
        exportScore.map(GuitarProDocument.init)
    }

    /// The track showing, ready to print (with the sequence's chords and tempo, for the sequence's tab).
    @MainActor
    var printContent: TabPrinter.Content? {
        guard let score = exportScore, let editor else { return nil }
        let chords = sequenceChords
        return TabPrinter.Content(score: score, track: editor.track,
                                  title: score.title.isEmpty ? displayName : score.title,
                                  tempo: sequenceTempo, chords: chords.isEmpty ? nil : chords)
    }

    /// The tab to export: the sequence's at the sequence's tempo, named after it if it has no title.
    private var exportScore: TabScore? {
        guard var score else { return nil }
        if let session = linkedSequence, let sequence = session.sequence {
            score.tempo = sequence.tempo
            if score.title.isEmpty { score.title = session.displayName }
        }
        return score
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

    /// Closes the tab (saving it first if it has a file). The sequence's tab stays while the sequence is open.
    func close() {
        guard !isSequenceTab else { return }
        stopPlaying()
        if fileURL != nil, hasUnsavedChanges {
            try? save()
        }
        clearState()
        defaults.removeObject(forKey: TabSession.lastFileKey)
        defaults.removeObject(forKey: TabSession.draftKey)
    }

    private func clearState() {
        autosave?.cancel()
        fileURL?.stopAccessingSecurityScopedResource()
        fileURL = nil
        editor = nil
        isLoading = true
        score = nil
        isLoading = false
        hasUnsavedChanges = false
        saveError = nil
        playhead = nil
        playheadPlace = nil
        clearUndo()
    }

    private func load(_ score: TabScore, from url: URL?) {
        editor = TabEditorState()
        fileURL = url
        isLoading = true
        self.score = score
        isLoading = false
        hasUnsavedChanges = false
        saveError = nil
        clearUndo()
    }

    // MARK: - Saving

    func save() throws {
        guard let score, let fileURL else { return }
        do {
            try score.encoded().write(to: fileURL, options: .atomic)
            hasUnsavedChanges = false
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            throw error
        }
    }

    /// Call after Save As has written the file: this becomes the tab's file. (For the sequence's tab, it was an
    /// export: the tab stays the sequence's.)
    func didSave(to url: URL) {
        guard !isSequenceTab else { return }
        if fileURL != url {
            fileURL?.stopAccessingSecurityScopedResource()
            _ = url.startAccessingSecurityScopedResource()
            fileURL = url
        }
        hasUnsavedChanges = false
        saveError = nil
        defaults.removeObject(forKey: TabSession.draftKey)
        remember(url)
    }

    var document: TabDocument? {
        exportScore.map(TabDocument.init)
    }

    private func scoreChanged(from old: TabScore?) {
        if let score { editor?.clamp(to: score) }
        guard !isLoading, let score, score != old else { return }
        recordUndo(from: old, to: score)
        // The sequence's tab goes into the sequence (which saves it, and plays it straight away)
        if isSequenceTab {
            sequenceSession?.setTablature(score)
            return
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
            } else if let score, let data = try? score.encoded() {
                defaults.set(data, forKey: TabSession.draftKey)
            }
        }
        autosave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: - Undo

    private(set) var canUndo = false
    private(set) var canRedo = false
    @ObservationIgnored private var undoStack: [TabScore] = []
    @ObservationIgnored private var redoStack: [TabScore] = []
    @ObservationIgnored private var lastChange = Date.distantPast
    @ObservationIgnored private var isUndoing = false

    /// Keeps the tab from before a change (changes in quick succession are one step).
    private func recordUndo(from old: TabScore?, to new: TabScore) {
        guard !isUndoing, let old, old != new else { return }
        if Date().timeIntervalSince(lastChange) > 0.5 || undoStack.isEmpty {
            undoStack.append(old)
            if undoStack.count > 200 { undoStack.removeFirst() }
        }
        lastChange = Date()
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    func undo() {
        guard let current = score, let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        restore(previous)
    }

    func redo() {
        guard let current = score, let next = redoStack.popLast() else { return }
        undoStack.append(current)
        restore(next)
    }

    private func restore(_ target: TabScore) {
        isUndoing = true
        score = target
        isUndoing = false
        lastChange = .distantPast
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func clearUndo() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastChange = .distantPast
        canUndo = false
        canRedo = false
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
        defaults.set(bookmark, forKey: TabSession.lastFileKey)
    }

    private func saveRecents() {
        defaults.set(try? JSONEncoder().encode(recents), forKey: TabSession.recentsKey)
    }

    /// Reopens the last file, or the unsaved draft.
    private func restore() {
        if let bookmark = defaults.data(forKey: TabSession.lastFileKey), (try? open(Recent(name: "", bookmark: bookmark))) != nil {
            return
        }
        if let data = defaults.data(forKey: TabSession.draftKey), let draft = try? TabScore.decode(from: data) {
            load(draft, from: nil)
            hasUnsavedChanges = true
        }
    }
}

// MARK: - Editing (the tab editor's keys and toolbar)

extension TabSession {
    private var trackIndex: Int { editor?.track ?? 0 }

    /// A fret typed on the cursor's string. A second digit within a moment makes a two-digit fret (up to 29).
    func typeDigit(_ digit: Int) {
        guard let editor, score != nil else { return }
        var fret = digit
        if let pending = editor.pendingDigit, pending.at == editor.cursor, Date().timeIntervalSince(pending.time) < 0.8,
           pending.fret * 10 + digit <= 29, pending.fret > 0 {
            fret = pending.fret * 10 + digit
        }
        let index = score!.setNote(track: trackIndex, at: editor.position, string: editor.cursor.string, fret: fret, duration: editor.duration)
        editor.cursor.beat = index
        editor.pendingDigit = (fret, Date(), editor.cursor)
        editor.selectionAnchor = nil
    }

    /// Next or previous beat. Past the end of a full bar it goes into the next bar (adding one after the last);
    /// a bar that isn't full yet stops at the slot for adding a beat.
    func moveBeat(by step: Int, extending: Bool = false) {
        guard let editor, var score else { return }
        if extending {
            if editor.selectionAnchor == nil { editor.selectionAnchor = editor.cursor }
        } else {
            editor.selectionAnchor = nil
        }
        let track = trackIndex
        var cursor = editor.cursor
        let count = score.beats(track: track, bar: cursor.bar).count
        if step > 0 {
            let atEnd = cursor.beat >= count || (cursor.beat == count - 1 && score.isFull(track: track, bar: cursor.bar))
            if !atEnd {
                cursor.beat += 1
            } else {
                if cursor.bar + 1 >= score.barCount {
                    score.insertBar()
                    self.score = score
                }
                cursor.bar += 1
                cursor.beat = 0
            }
        } else {
            if cursor.beat > 0 {
                cursor.beat -= 1
            } else if cursor.bar > 0 {
                cursor.bar -= 1
                let previous = score.beats(track: track, bar: cursor.bar).count
                cursor.beat = score.isFull(track: track, bar: cursor.bar) ? max(previous - 1, 0) : previous
            }
        }
        editor.cursor = cursor
        if let beat = editor.beat(in: self.score ?? score) {
            editor.duration = beat.duration
        }
        editor.pendingDigit = nil
    }

    func moveString(by step: Int) {
        guard let editor, let score, score.tracks.indices.contains(trackIndex) else { return }
        editor.cursor.string = min(max(editor.cursor.string + step, 0), score.tracks[trackIndex].stringCount - 1)
        editor.pendingDigit = nil
    }

    /// Backspace: the selected beats, or the note on the cursor's string, or (on a rest) the beat itself.
    func deleteAtCursor() {
        guard let editor, let current = score else { return }
        if let selection = editor.selection {
            score?.removeBeats(track: trackIndex, from: selection.start, to: selection.end)
            editor.cursor.bar = selection.start.bar
            editor.cursor.beat = selection.start.beat
            editor.selectionAnchor = nil
        } else if let beat = editor.beat(in: current) {
            if beat.notes.contains(where: { $0.string == editor.cursor.string }) {
                score?.removeNote(track: trackIndex, at: editor.position, string: editor.cursor.string)
            } else if beat.isRest {
                score?.removeBeat(track: trackIndex, at: editor.position)
            }
        }
        if let score { editor.clamp(to: score) }
    }

    func makeRest() {
        guard let editor else { return }
        score?.setRest(track: trackIndex, at: editor.position, duration: editor.duration)
    }

    func insertBeat() {
        guard let editor else { return }
        score?.insertBeat(track: trackIndex, at: editor.position, duration: editor.duration)
    }

    func toggleTie() {
        guard let editor else { return }
        score?.toggleTie(track: trackIndex, at: editor.position, string: editor.cursor.string)
    }

    /// Shorter (-1) or longer (+1) note value, for the selected beats or the beat at the cursor, and for new beats.
    func changeDuration(by step: Int) {
        guard let editor else { return }
        let values = TabDuration.Value.allCases   // whole ... 64th
        guard let index = values.firstIndex(of: editor.duration.value) else { return }
        let next = values[min(max(index - step, 0), values.count - 1)]
        applyDuration { $0.value = next }
    }

    func toggleDot() {
        applyDuration { $0.dots = $0.dots == 0 ? 1 : 0 }
    }

    func toggleTriplet() {
        applyDuration { $0.tuplet = $0.tuplet == nil ? .triplet : nil }
    }

    func setDuration(_ value: TabDuration.Value) {
        applyDuration { $0.value = value }
    }

    private func applyDuration(_ change: (inout TabDuration) -> Void) {
        guard let editor, let current = score else { return }
        var duration = editor.beat(in: current)?.duration ?? editor.duration
        change(&duration)
        editor.duration = duration
        let positions: [TabPosition]
        if let selection = editor.selection {
            positions = (selection.start.bar...selection.end.bar).flatMap { bar -> [TabPosition] in
                let count = current.beats(track: trackIndex, bar: bar).count
                let first = bar == selection.start.bar ? selection.start.beat : 0
                let last = bar == selection.end.bar ? min(selection.end.beat, count - 1) : count - 1
                return first <= last ? (first...last).map { TabPosition(bar: bar, beat: $0) } : []
            }
        } else {
            positions = [editor.position]
        }
        var updated = current
        for position in positions {
            updated.updateBeat(track: trackIndex, at: position) { beat in
                change(&beat.duration)
            }
        }
        score = updated
    }

    // MARK: Copy and paste

    func copySelection() {
        guard let editor, let score else { return }
        let range = editor.selection ?? (editor.position, editor.position)
        editor.clipboard = score.beats(track: trackIndex, from: range.start, to: range.end)
    }

    func cutSelection() {
        copySelection()
        guard let editor else { return }
        if editor.selection == nil, editor.beat(in: score!) != nil {
            score?.removeBeat(track: trackIndex, at: editor.position)
        } else {
            deleteAtCursor()
        }
    }

    func paste() {
        guard let editor, !editor.clipboard.isEmpty else { return }
        score?.insertBeats(editor.clipboard, track: trackIndex, at: editor.position)
        editor.cursor.beat += editor.clipboard.count
        editor.selectionAnchor = nil
    }
}

// MARK: - Techniques

extension TabSession {
    /// Things a note either has or hasn't.
    enum Technique: CaseIterable {
        case legato, slide, vibrato, palmMute, letRing, dead, ghost, harmonic, tapped, accent

        func isOn(_ note: TabNote) -> Bool {
            switch self {
            case .legato: return note.legato
            case .slide: return note.slide != nil
            case .vibrato: return note.vibrato
            case .palmMute: return note.palmMute
            case .letRing: return note.letRing
            case .dead: return note.isDead
            case .ghost: return note.isGhost
            case .harmonic: return note.harmonic != nil
            case .tapped: return note.tapped
            case .accent: return note.accent
            }
        }

        func set(_ on: Bool, on note: inout TabNote) {
            switch self {
            case .legato: note.legato = on
            case .slide: note.slide = on ? .shift : nil
            case .vibrato: note.vibrato = on
            case .palmMute: note.palmMute = on
            case .letRing: note.letRing = on
            case .dead: note.isDead = on
            case .ghost: note.isGhost = on
            case .harmonic: note.harmonic = on ? .natural : nil
            case .tapped: note.tapped = on
            case .accent: note.accent = on
            }
        }
    }

    /// The notes a technique applies to: every note in the selected beats, or the note on the cursor's string.
    private var techniqueTargets: [(TabPosition, Int)] {
        guard let editor, let score else { return [] }
        let track = editor.track
        if let selection = editor.selection {
            return (selection.start.bar...selection.end.bar).flatMap { bar -> [(TabPosition, Int)] in
                let beats = score.beats(track: track, bar: bar)
                let first = bar == selection.start.bar ? selection.start.beat : 0
                let last = bar == selection.end.bar ? min(selection.end.beat, beats.count - 1) : beats.count - 1
                guard first <= last, beats.indices.contains(first) else { return [] }
                return (first...last).flatMap { beat in beats[beat].notes.map { (TabPosition(bar: bar, beat: beat), $0.string) } }
            }
        }
        guard let beat = editor.beat(in: score), beat.notes.contains(where: { $0.string == editor.cursor.string }) else { return [] }
        return [(editor.position, editor.cursor.string)]
    }

    private func targetNotes() -> [TabNote] {
        guard let editor, let score else { return [] }
        return techniqueTargets.compactMap { position, string in
            score.beats(track: editor.track, bar: position.bar)[position.beat].notes.first { $0.string == string }
        }
    }

    /// Whether the notes it would apply to all have it (for ticks in the menu).
    func isOn(_ technique: Technique) -> Bool {
        let notes = targetNotes()
        return !notes.isEmpty && notes.allSatisfy(technique.isOn)
    }

    /// On for all of them, or off if they all have it already.
    func toggle(_ technique: Technique) {
        let on = !isOn(technique)
        changeTargets { technique.set(on, on: &$0) }
    }

    func setBend(_ bend: TabNote.Bend?) {
        changeTargets { $0.bend = bend }
    }

    func setSlide(_ slide: TabNote.Slide?) {
        changeTargets { $0.slide = slide }
    }

    func setHarmonic(_ harmonic: TabNote.Harmonic?) {
        changeTargets { $0.harmonic = harmonic }
    }

    /// B: no bend → full → half → full and release → pre-bend and release → none.
    func cycleBend() {
        let options: [TabNote.Bend?] = [nil, .up(200), .up(100), .upAndRelease(200), .prebendRelease(200)]
        let current = targetNotes().first?.bend
        let index = options.firstIndex { $0 == current } ?? 0
        setBend(options[(index + 1) % options.count])
    }

    /// ⇧S: the slides that don't go to another note, in turn.
    func cycleSlideInOut() {
        let options: [TabNote.Slide?] = [nil, .inFromBelow, .inFromAbove, .outDownwards, .outUpwards]
        let current = targetNotes().first?.slide
        let index = options.firstIndex { $0 == current } ?? 0
        setSlide(options[(index + 1) % options.count])
    }

    private func changeTargets(_ change: (inout TabNote) -> Void) {
        guard let editor, var updated = score else { return }
        for (position, string) in techniqueTargets {
            updated.updateNote(track: editor.track, at: position, string: string, change)
        }
        score = updated
    }
}
