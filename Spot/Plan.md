# Spot — Plan

## Decisions so far

| Topic | Decision |
|---|---|
| Platform | Bump to **macOS 14+**. Use **SwiftData** for persistence and **@Observable** for state. Drop the unused SQLite.swift dependency. |
| Instruments | **Guitar and piano**. The visualiser must not assume a fretboard. Guitar supports any tuning or string count. |
| Tabs | **Library → Chord Practice → Sequencer → Settings**. The Editor tab goes away. Editing happens in the Library detail panel or a sheet. |
| Distribution | **Undecided**, so default to **permissive licences** (MIT/BSD/Apple frameworks). No GPL dependencies (Rubber Band, aubio, Essentia). |
| Sequencer analysis | ~~Auto beats and auto chords in v1~~ **Dropped (Oct 2026):** the grid is set by tap tempo and warp markers, and chords are entered by hand. |
| Sound | Metronome/count-in, audition notes/chords, backing for sequences with no audio, recording your playing. Notes go out over **MIDI** in v1; an internal sampler/SoundFont comes later. |
| Fingerings | **Generate and curate**: generate shapes from formula + tuning, ship a curated set, and let the user save edits. |
| Sequence storage | **`.spot` document packages**, so the app becomes document-based for sequences. |
| Imported audio | **Referenced, not copied.** Store a security-scoped bookmark plus the warp and analysis data in the document. |
| Spelling | **Follows the key** (F# in D major, Bb in F major). |
| Piano | **Secondary.** Guitar comes first. Piano shows finger numbers where they're available, but it is built after the guitar features. |

---

## Glossary (fixes the current "inversion" overloading)

The code currently uses `Inversion` both for chord inversions and for selecting a scale's 3NPS position. Those are different things. These are the terms from now on:

- **Formula**: the spelled degrees of a scale or chord, e.g. `1 b3 5 b7`. This is the source of truth, not an enum case.
- **Mode**: a rotation of a parent scale, e.g. Dorian = Major from degree 2. Modes are separate scale definitions linked to a parent and a degree.
- **Inversion** (chords only): which chord tone is in the bass.
- **Voicing** (chords only): which chord tones are used and in what octave and order (close, drop-2, drop-3, shell, spread, rootless).
- **Shape / Position**: a concrete layout on an instrument, e.g. CAGED "E shape", 3NPS position 2, pentatonic box 1, a drop-2 voicing on strings 2–5.
- **Fingering**: a shape plus finger assignments (optional).

---

## Current state audit

### What exists
- Library tab: fuzzy-searchable list of hardcoded scales, chords and intervals, favourite toggle, tree filter sidebar (placeholder data), detail panel with interval banner. `IntervalMatrixView` is a stub.
- Fretboard: 6-string, 24 frets, hardcoded standard tuning. Interval colouring, hide unrelated notes, label mode, highlight mode.
- 3NPS patterns: hardcoded for the 7 major modes only.
- Footer: root note picker, BPM, transport buttons (UI only, no audio).
- Editor / Sequence / Settings tabs: placeholders.
- No persistence, no audio, no tests (the `Tests/` and `Sources/` folders are an unconnected SPM template).

### Bugs to fix
Wrong formulas ([ScaleType.swift](Enums/Scales/ScaleType.swift), [ChordType.swift](Enums/Chords/ChordType.swift)):
- `LydianAugmented` should be `1 2 3 #4 #5 6 7`. It is currently `1 b2 b3 #4 b6 6 b7`.
- `SuperLocrianbb7` should end with `bb7` (`.VI`), not `.bVII`.
- `Blues` is a copy of Major Pentatonic. It should be `1 b3 4 b5 5 b7`.
- `Dim` should be `1 b3 b5` (`.TT`), not `.bVI`. `Dim7` should be `1 b3 b5 bb7`.
- `Dom7Sharp9` uses `.bIX` (b9). It should be `#9` (`.bX`).
- `Dom7b9` is `1 3 5 #9`. It should be `1 3 5 b7 b9`.
- `SixNine` is missing the 6.
- `Maj13` contains both `.VI` and `.XIII`.

Crashes and logic errors:
- [NoteService.swift](Services/NoteService.swift): `inversion.rawValue + 1 % 7` binds as `rawValue + 1` because `%` is evaluated before `+`, so the index is never wrapped. Selecting Locrian and pressing ⌘2 indexes `patterns[7]` and **crashes**. Dorian crashes from ⌘7, etc.
- [Library.swift](Models/Library.swift): `refresh()` rebuilds every `LibraryItem` on each search keystroke, so **favourites are lost** when you type in the search box.
- [FretboardView.swift](Views/FretboardView.swift): `getHighlightedNotesforScale` is called **inside the per-marker loop**, about 150 times per render. Each call builds a new pattern object and runs 3 unused `getPatterns` calls.
- [InstrumentView.swift](Views/InstrumentView.swift): a new `FretboardViewModel` is created on every body evaluation. `onNoteClicked` uses `appState.labelMode` while `init` uses `.interval`, so the label behaviour depends on which path ran last.
- [Footer.swift](Views/Layout/Footer.swift): there is an unused local `@State bpm`, and the transport state lives only in the `Transport` view.

### Structural problems the plan addresses
1. **Theory is enum-hardcoded.** Scales and chords are `enum` cases, with the display name as the raw value. They can't be user-extended, imported or persisted.
2. **No spelling.** `Note` is a pitch class (A=0) with fixed flat names. `Interval` mixes semitones with degree names and lacks `X`, `XII`, `bb7`, etc. Correct chord naming, `#4` vs `b5`, and key-aware spelling (F# in D major, not Gb) all need spelled notes.
3. **Fretboard-specific logic is everywhere.** Piano needs the "what to highlight" logic separated from the "how to draw it" logic.
4. **State is one big `ObservableObject`.** Every published change re-renders everything.

### Repo hygiene
- `build/` (152 MB, 3,154 files) is **committed**. Add `build/` to `.gitignore` and `git rm -r --cached build`.
- `Package.swift`, `Sources/` and `Tests/` are an SPM template that isn't wired to the Xcode project. Repurpose them as `SpotCore` (see Phase 0).
- `SpotDocument.swift` is still the Xcode template. It will be reused for sequence documents.
- Delete `LegacyTableView.swift`, the empty `Mode.swift`, the commented-out `DatabaseManager.swift`, and the `Data/*.json` stubs once the new formats exist.

---

## Phase 0 — Foundations

These come first because all three tabs depend on them.

### 0.1 `SpotCore` Swift package
Move music theory, models and (later) audio analysis into a local SPM package with no SwiftUI dependency. The app target depends on it. This gives `swift test` for the theory engine, and the formula bugs above become test cases.

```
SpotCore/
  Theory/      PitchClass, SpelledNote, Degree, Formula, Key, ChordSymbol parser
  Library/     ScaleDefinition, ChordDefinition, Shape, LibraryBundle (import/export)
  Instrument/  Tuning, Fretboard, Keyboard, ShapeGenerator
  Harmony/     ChordScaleMatcher (shared by Chord Practice and Sequencer)
  Analysis/    (Phase 3) onset, tempo, beat, chroma, chord recognition
```

### 0.2 Theory model
```swift
struct PitchClass { var value: Int }            // 0...11, C = 0 (switch from A = 0 to match MIDI)
struct SpelledNote { var letter: Letter; var accidental: Int }  // F#, Gb, Cbb
struct Degree { var number: Int; var accidental: Int }          // b3, #11, bb7 — semitones derived
struct Formula { var degrees: [Degree] }        // optional degrees (e.g. the 5 in 9th chords) live on ChordDefinition

struct ScaleDefinition: Identifiable, Codable {
    var id: String              // stable, e.g. "builtin.scale.dorian" or UUID for user items
    var name: String; var aliases: [String]
    var formula: Formula
    var family: String?         // "Major modes", "Melodic minor modes", "Pentatonic", "Symmetric"
    var parent: (id: String, degree: Int)?   // for modes
    var tags: [String]; var source: Source   // .builtin / .user / .imported(bundle)
}

struct ChordDefinition: Identifiable, Codable {
    var id: String; var name: String
    var symbols: [String]       // ["maj7", "Δ7", "M7"], the first is the display default
    var formula: Formula
    var tags: [String]; var source: Source
}
```
- Built-in definitions ship as a bundled JSON `LibraryBundle` (same format as import/export), not Swift enums.
- The chord symbol parser (`"Bb7#9/D"` → root, definition, bass) is needed by Chord Practice input, the Sequencer chord lane and import.
- `Inversion` becomes a chord-only concept: `bassDegree: Degree?` on a chord instance.

### 0.3 Instrument abstraction
```swift
protocol InstrumentLayout {           // what "positions" exist
    func positions(of pitch: PitchClass) -> [Position]
}
struct Fretboard: InstrumentLayout { var tuning: Tuning; var frets: Int }   // Position = (string, fret)
struct Keyboard: InstrumentLayout { var range: ClosedRange<Int> }          // Position = MIDI note
```
- Views receive a precomputed `[Marker]` (position, label, role, colour, emphasis) and only draw it. All "is this note highlighted / in collection / in this shape" logic moves to a model that recomputes once per state change, not per marker per frame.
- `Tuning` is a stored, user-editable entity: name, open strings (with octave), and string count. Presets: Standard, Drop D, DADGAD, Open G, 7-string, 4/5-string bass.
- Add a new `KeyboardView`. The instrument choice lives in Settings plus a quick toggle.

### 0.4 State and persistence
- Replace `AppState` with `@Observable` stores split by concern: `SelectionState` (root, current scale/chord, shape), `DisplaySettings` (labels, hide unrelated, etc.), `TransportState`, `LibraryStore`.
- **SwiftData** for user data: favourites, ratings, tags, user-created definitions and shapes, tunings. Simple display preferences use UserDefaults.
- Built-in definitions are loaded from the bundled JSON. User state (favourite, rating, tags) is stored separately and keyed by definition `id`, so built-ins can be updated without wiping user data.
- **Sequences are files** (`.spot` package): an audio reference + analysis + warp markers + chord lane. They can be shared and opened from Finder. They open inside the Sequence tab of the single main window (no separate document windows), with Spot handling open/save/autosave itself.

### 0.4a Key-aware spelling
- Every displayed note is spelled from a context: the current key (Sequencer and Chord Practice), or the root's natural key (Library).
- Rules: scale notes use each letter once (D major → F#, C#). Chord tones are spelled from the chord root's degrees (Bb7 → Bb D F Ab). Root pickers choose the conventional spelling (Bb, Eb, F#, Ab, Db), and the user can override it per sequence or key.
- Tests: all 12 major and minor keys, plus the theoretical edge cases (G# major → F##; prefer Ab major in the UI).

### 0.5 Theme
Finish moving the hardcoded colours (Header, Footer, TabView, LibraryList, FretboardViewModel) into `Theme`, and load them from `Theme.json`. A low-priority task, but best done while the views are being refactored anyway.

---

## Tab 1 — Library (scales and arpeggios)

*Original:* mostly implemented. It needs a better way to store and represent inversions and variations, then populate all known chords and scales with common fingerings. It must be user-extendable with import/export.

### 1.1 Shapes (positions, voicings, fingerings)
```swift
struct Shape: Identifiable, Codable {
    var id: String
    var definitionId: String          // scale or chord it realises
    var system: String                // "CAGED", "3NPS", "Pentatonic box", "Drop 2", "Shell", "Custom"
    var name: String                  // "E shape", "Position 3", "Drop 2 – strings 1-4, root in bass"
    var instrument: InstrumentKind    // .guitar / .piano
    var tuningId: String?             // guitar only; shapes are tuning-specific
    var notes: [ShapeNote]            // root-relative, so the shape transposes by moving the anchor
    var inversion: Degree?            // chords: bass degree
    var source: Source
}
struct ShapeNote: Codable {
    var string: Int?; var fretOffset: Int?    // guitar: relative to anchor fret
    var octaveOffset: Int?                    // piano
    var degree: Degree
    var finger: Int?                          // optional fingering, 1-4 / T
}
```

### 1.2 Generators (the "generate" half of "generate and curate")
- **Scales:** 3NPS (any 7-note scale, 7 positions). CAGED (5 positions, any scale, by filtering to a 4–5 fret span around each CAGED chord root). Pentatonic boxes. Single-string / horizontal. "Positions within frets X–Y" for any scale.
- **Arpeggios:** the same position systems applied to chord tones only, plus sweep-style shapes (one note per string where possible).
- **Chord voicings:** enumerate playable voicings for any formula on any tuning, constrained by fret span (≤4–5), string sets, one note per string, max stretch, and required vs optional degrees. Label them by system: close, drop-2/drop-3, shell (1-3-7), rootless, triads on string sets, and each inversion.
- **Piano (secondary, later):** close position and inversions, plus common LH/RH splits (shell in LH, upper structure in RH).
- **Guitar fingers:** assign fingers to generated shapes with a simple rule: index finger on the lowest fret in the span, one finger per fret, and a barre when several strings share the lowest fret. Users can override per note. Curated shapes carry hand-checked fingerings.
- **Piano fingers:** curated standard fingerings for the major/minor scales in all keys (well documented). Chord and arpeggio fingerings come from simple rules (thumb on lowest in RH, 5-3-1 / 5-2-1 patterns), with no fingering shown where the rule isn't confident.
- Generated shapes are computed on demand and cached. Saving or editing a generated shape creates a user `Shape`.

### 1.3 Curated content
Built-in bundle, roughly 60+ scales and 100+ chord types:
- **Scales:** major modes; melodic minor modes; harmonic minor modes; harmonic major modes; pentatonics (major, minor, Egyptian, Japanese/In-Sen, Hirajoshi, etc.); blues (minor, major); bebop (dominant, major, minor); symmetric (whole tone, half-whole and whole-half diminished, augmented); exotic/regional (Hungarian minor, double harmonic, Neapolitan major/minor, Persian, etc.).
- **Chords:** triads (maj, min, dim, aug, sus2, sus4); 6ths; all 7th qualities; 9/11/13 with alterations; add chords; power chords; quartal; and slash chords via the parser rather than as separate entries.
- **Shapes:** standard CAGED for major/minor/dom7/maj7/m7, common jazz drop-2/drop-3, and shell voicings. Everything else is generated.
- Validate each formula against an independent reference (a script that cross-checks with a known dataset such as the `tonal` JS library's dictionaries) to avoid repeating the bugs above.

### 1.4 Library UI changes
- Tree sidebar becomes real filters: Type, Family, Tags, Favourites, Source (built-in, mine, imported bundle).
- Detail panel: name, aliases, formula with spelled notes in the current key, list of shapes (pick to show on the instrument), "related" (parent scale and sibling modes, chords built on each degree via a working `IntervalMatrixView`, and scales containing this chord), plus Edit/Duplicate.
- Replace the inversion shortcuts (⌘1–7) with "previous/next shape" (e.g. ⌘[ / ⌘]) plus chord-inversion shortcuts that only apply to chords.
- Add a definition editor (sheet): name, formula entry by clicking degrees or typing `1 b3 5 b7`, live preview on the instrument, and tags.
- Add a shape editor: click frets or keys to toggle notes, set finger numbers, then save.

### 1.5 Import / export
- One versioned JSON format, `LibraryBundle`, also used for the built-in data. File extension `.spotlib` with a custom UTType.
```json
{
  "format": "spot.library", "version": 1,
  "bundle": { "id": "com.brian.jazz-voicings", "name": "Jazz voicings", "author": "Brian" },
  "tunings": [ { "id": "standard-6", "name": "Standard", "strings": ["E2","A2","D3","G3","B3","E4"] } ],
  "scales":  [ { "id": "...", "name": "Dorian", "formula": "1 2 b3 4 5 6 b7", "parent": { "id": "builtin.scale.major", "degree": 2 }, "tags": [] } ],
  "chords":  [ { "id": "...", "name": "Minor seventh", "symbols": ["m7","-7"], "formula": "1 b3 5 b7", "optional": ["5"] } ],
  "shapes":  [ { "id": "...", "definition": "...", "system": "Drop 2", "tuning": "standard-6",
                 "notes": [ { "string": 4, "fret": 0, "degree": "1", "finger": 2 } ] } ]
}
```
- Formulas are strings (`"1 b3 5 b7"`) so they can be written by hand.
- On import, show what's new or conflicting (same `id`), with a choice to skip, replace or keep both.
- Export everything, a selection, or a tag.
- Optionally import **MusicXML/ChordPro chord symbols**. This belongs to the Sequencer rather than the Library.

---

## Tab 2 — Tab editor (replaces Chord Practice, Oct 2026)

Chord Practice is removed: the Sequencer now does its job (a scale, voicing and position per chord, intervals, what's next). Its unique parts (ranked scale list with reasons, arpeggio/upper-structure suggestions, voicing browser) can return later as a chord inspector in the Sequencer. The second tab becomes a **tab (tablature) editor**.

Decisions:
- **Files:** Spot's own format, `.spottab` (JSON, UTI `iko.spot.tab`), opened in the tab like sequences (New / Open / Recent / Save / autosave, one at a time).
- **Guitar Pro:** import `.gp` (GP7/8), `.gpx` (GP6), `.gp5` / `.gp4` / `.gp3`; export `.gp` (GP7) so files go back into Guitar Pro. Readers and writers are written in SpotCore (no permissively licensed Swift library exists), tested against small files built in the tests and, where possible, real files. Formats: GP7/8 is a zip holding `Content/score.gpif` (XML); GP6 wraps the same XML in a compressed container (BCFZ/BCFS); GP3–5 are a documented binary format. Zip reading/writing uses the Compression framework (raw deflate) with our own container code.
- **Scope v1:** core notation (notes by string and fret, durations with dots and tuplets, rests, ties, bars, time and key signatures, tempo and tempo changes, repeats and section markers), techniques (hammer-on / pull-off, slides, bends with amounts, vibrato, palm mute, let ring, dead and ghost notes, harmonics, tapping), and multiple tracks (each with tuning, string count and capo). Tab only: no standard-notation staff in v1.
- **Sequences:** tab files stay separate, but a sequence can link one so it plays along with the sequence's audio and chords, and a tab's chord names can become sequence chords.

Model (`SpotCore/Tab`): `TabScore` (title, artist, tempo, master bars, tracks) → `MasterBar` (time signature, key, repeats, marker, tempo change) and per-track `TabBar` → voices → `TabBeat` (duration, dots, tuplet, rest, notes, chord name, text) → `TabNote` (string, fret, tie, techniques).

Editing (v1): a cursor on string + beat; type fret numbers, arrows to move, number-row keys or a palette for durations, shortcuts for techniques (H/P, S, B, V, M, L, X…), insert/delete beats and bars, copy/paste, undo/redo. The fretboard above shows the notes at the cursor (or playing), with fingers.

## Tab 2 (old) — Chord Practice (removed Oct 2026)

*Original:* see which scales and arpeggios you can play over different chords, highlighting the chord position in all voicings and positions, and the scale positions relative to them.

### 2.1 Harmony engine (`ChordScaleMatcher`, shared with the Sequencer)
Input: a chord (root + definition + optional bass) and an optional context (key and the previous and next chord).
Output, ranked:
- **Compatible scales:** scales that contain all chord tones, spelled from the chord root (e.g. Dm7 → D Dorian, D Aeolian, D Phrygian…). Score them by:
  - diatonic to the context key (if given),
  - number of avoid notes (a half step above a chord tone, e.g. the 4 over maj7),
  - commonness (a curated weight per scale),
  - smoothness from the previous chord's chosen scale (fewest changed notes).
- **Arpeggios:** the chord itself; upper-structure arpeggios whose tones sit inside a compatible scale (e.g. over Cmaj7: Em7 = 3-5-7-9, G triad = 5-7-9, Bm7b5 = 7-9-11-13); and guide-tone pairs (3 and 7).
- **Tension map:** for each of the 12 pitch classes, its role over this chord: chord tone, available tension, avoid note, or outside.

### 2.2 UI
- Chord input: a symbol text field with the parser (`G7b9`), or root + type pickers. Optionally a short progression (`Dm7 G7 Cmaj7`) to step through with ←/→.
- Left list: ranked scales and arpeggios with a score explanation ("diatonic to C major, 0 avoid notes").
- Instrument:
  - The **chord voicing** is drawn solid (filled markers).
  - The **selected scale or arpeggio** shape is drawn around it, restricted to the same neck region (±2 frets of the voicing).
  - Colour by **role** (chord tone / tension / avoid) or by interval, switchable.
  - Cycle **voicing position** up the neck (⌘[ / ⌘]). The scale shape follows to the matching position, so you always see "this chord here, and what's under my fingers here".
  - A "Whole neck" toggle shows everything.
- Piano: the chord in the LH/RH split, and scale tones marked across two octaves.
- Audition: click the chord to hear it, and click a scale to hear it ascending (uses the audio engine from 3.4).

---

## Tab 3 — Sequencer

*Original:* import audio and decorate it with chords and scales. Time-warp, stretch and remap to a grid like Logic/Ableton. On playback, hear the track and see the configured options. Visualise where you are and where you're going next.

### 3.1 Sequence document (`.spot` package)
```
MySong.spot/
  sequence.json      tempo map, time signature(s), warp markers, chord regions, sections, loop, mixer
  (sequence.json also holds the audio reference: security-scoped bookmark, last known path,
   duration, sample rate, content hash of the file's first/last megabyte, and the warp markers)
  takes/             recordings of your playing (these are owned, so they are stored here)
  cache/             analysis results, warped renders, waveform overview (rebuildable, not essential)
```
- **Audio by reference:** the source file is never copied. Warp markers are stored in **source-time seconds**, so they stay valid as long as the file is the same audio.
- **Missing or moved file:** resolve the bookmark first, then the last known path, then show a "Locate file…" prompt. Accept the relinked file only if its duration and hash match, or warn if they don't ("different audio, warp markers may not line up").
- Sandbox: requires the `com.apple.security.files.bookmarks.app-scope` / user-selected read-only entitlements. Start and stop security-scoped access around playback and analysis.
- `cache/` can be deleted at any time and is regenerated from the source audio.
- **Timeline unit = beats** (musical time). Audio time maps to beats through warp markers.
- **Chord regions:** start beat, length, chord (root/definition/bass), an optional pinned scale and shape (otherwise the engine's top suggestion), and optional notes ("solo here").
- **Sections:** named ranges (Intro/Verse/Chorus) for navigation and looping.
- A sequence **without audio** is valid: it is a backing/practice progression played by the internal instrument.

### 3.2 Audio analysis (auto beats + chords, manual correction)
All in-house on Accelerate/vDSP to keep licensing permissive. Runs in the background on import, with a progress indicator. Results are cached in the package.
1. **Onset strength:** STFT → spectral flux (log-magnitude, half-wave rectified).
2. **Tempo:** autocorrelation of onset strength + tempo prior around 120 BPM → candidate BPMs. Show the top 2–3 so a "double/half time" error is one click to fix.
3. **Beats:** dynamic-programming beat tracker (Ellis 2007), well documented and about 100 lines. Downbeats come from a bar-length periodicity + low-frequency energy heuristic. The user can shift the downbeat.
4. **Chords:** beat-synchronous chroma (constant-Q or log-frequency STFT folded to 12 bins) → template matching against maj/min/7/maj7/m7/dim/sus → Viterbi/HMM smoothing → chord regions snapped to beats.
   - Accuracy expectation: ~60–75% on pop/rock, worse on jazz/dense mixes. The UI must make fixing chords fast.
   - Later upgrade path: a Core ML chord model (e.g. a converted CNN/CRNN trained on public datasets). Check the licence of the model and weights.
5. **Key estimation** (Krumhansl-Schmuckler on summed chroma) to give Chord Practice its context key.

**Correction tools:** drag warp markers, tap tempo, "set this beat as bar 1", nudge the grid. Chord lane: click to edit with the symbol parser, split/merge regions, drag edges (snap to beat/half-bar/bar), "apply to all similar sections".

### 3.3 Warping / time-stretch
- **Warp markers** map source time to beat. Between markers, playback rate is piecewise-linear, so the track lines up with a strict grid.
- **Engine:** [Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch) (MIT, header-only C++) via a small Obj-C++/C wrapper. It handles both warping and a global tempo change (practice slow-down without pitch change). It can also transpose pitch for playing in a different key.
- **v1 strategy:** render the warped audio **offline** into a cached buffer in the background whenever markers change, and play that with `AVAudioPlayerNode`. For live practice tempo (e.g. 70%), use a second pass or a real-time stretch node. Offline rendering keeps the real-time path simple; move to fully real-time later if editing latency is annoying.
- Waveform overview: precompute min/max peaks per N samples, stored in `cache/`.

### 3.4 Audio engine (shared app-wide)
`AVAudioEngine` graph:
```
Track player (warped buffer) ─┐
Metronome (scheduled click buffers) ─┼─► Mixer ─► Output
(later) Instrument (AVAudioUnitSampler) ─┘
Input (audio interface) ─► Recorder (file) + optional monitoring

Note events (audition, backing) ─► MIDI out (virtual source "Spot" + chosen destinations)
                                 └─► (later) internal sampler
```
- **Transport clock** in beats, owned by a `TransportState` model. Sample-accurate scheduling (`AVAudioTime`) for the metronome, chord backing and the UI playhead. The UI reads the position via `TimelineView(.animation)`; it does not drive it.
- **Metronome / count-in:** accent on beat 1, configurable count-in bars, and mute or level per sequence.
- **Audition and backing via MIDI (v1):** all note output goes through a `NoteOutput` protocol. The v1 implementation is **MIDI out** with CoreMIDI: a virtual source called "Spot" that a DAW or synth can listen to, plus an optional direct send to a chosen destination, with a configurable channel. Notes are timestamped from the transport clock (`MIDITimeStamp`) so backing stays in time with the track.
  - The metronome stays as internal audio, because it needs to work with no MIDI setup. It can optionally also be sent over MIDI.
  - Backing styles to start: sustained pad, strummed on each beat, simple comp pattern. Strums are generated as staggered note-ons across the voicing's strings.
  - **Later:** a second `NoteOutput` using `AVAudioUnitSampler` with a SoundFont (guitar/piano, checking sample licences). Apple's built-in GM sounds make a zero-asset stopgap if wanted.
- **MIDI in (later, optional):** light up notes played on a MIDI guitar or keyboard on the instrument view. This reuses the same CoreMIDI client.
- **Recording:** input from the chosen device, recorded to a take inside the `.spot` package, aligned to the timeline. Takes are listed per sequence. Requires the `com.apple.security.device.audio-input` entitlement and a microphone usage description. Latency compensation setting.
- **Loop:** loop a region or section. Practice mode can raise the tempo by N% after each pass.

### 3.5 Visualising "where am I / where next"
Suggestions, best first. I'd build **A + B** first and add **C** later.

- **A. Chord lane with playhead (Logic chord track / Chordify style).** A horizontal strip above the waveform shows chord blocks on the grid. The playhead is fixed at about 25% from the left and the lane scrolls. The current chord is large and highlighted, the next is smaller with a countdown ("in 3 beats"), and beat dots pulse for the current bar. This is the cheapest option and gives the most orientation.
- **B. Ghosting the next change on the instrument.** The current chord/scale is drawn normally. In the last 1–2 beats before a change, the next chord's tones fade in as **outline markers**:
  - **Common tones** (in both) get a special ring, so you know which notes keep working across the change.
  - **Target notes:** the next chord's 3rd and 7th nearest your current position pulse. That is where to land on the downbeat.
  - Optional **guide-tone arrows**: a short line from a current-chord 3rd/7th to the nearest next-chord tone (usually a half or whole step). This shows voice leading directly on the neck.
- **C. Position-aware suggestions.** Remember which neck region you're in (the selected shape's fret range). At each change, pick the next scale or arpeggio shape **closest to the current position** instead of jumping across the neck. A small arrow shows the shift if a move is needed.
- **D. Mini "next" instrument.** A small second fretboard or keyboard under the main one always shows the next chord's shape. Simple and clear, but costs vertical space.
- **E. Rhythm-game highway (Rocksmith style).** Notes and chords scroll toward the fretboard. Great for fixed melodies or riffs, but heavy to build and less suited to "here's a scale, improvise". Worth keeping for a future riff/lick feature.
- **F. Lyric/chart view.** A full-screen chord chart (bars in rows, like a Real Book page) with the current bar highlighted. Good as an alternative view for reading a whole form at once.

### 3.6 Sequencer UI layout
```
┌ Instrument (fretboard or keyboard, with ghosting) ───────────────────────────┐
├ Sections:  | Intro |   Verse   |  Chorus  |   Verse   | …                  ┤
├ Chords:    | Am7  | D7  | Gmaj7 | Cmaj7 | F#ø  | B7  | Em  …   ▶ next: D7 in 3 ┤
├ Grid/bars: 1 . . . 2 . . . 3 . . . 4 …   (warp markers as draggable flags)   ┤
├ Waveform:  ▁▃▅▇▅▃▂▁▃▅▇▇▅▃ …     │playhead                                    ┤
└ Footer transport: count-in · metronome · ⏮ ▶ ⏭ · loop · tempo % · key · BPM ┘
```

---

## Settings tab
- Instrument (guitar/piano), tuning picker and editor, fret count.
- Low priority: a flipped fretboard (left-handed and/or low string at top). The default stays as it is now, high E at the top as in tab and standard guitar documentation.
- MIDI: output destination(s), channel, "send metronome over MIDI".
- Label mode defaults, colour scheme by interval or by role, theme.
- Audio: output and input device, buffer size, latency compensation, metronome sound and level, instrument sound.
- Library: manage imported bundles, export all, reset built-ins.

---

## Testing
- `SpotCore` unit tests:
  - every built-in formula against reference data;
  - the spelling round-trip (`"F#m7b5"` → notes → name);
  - the chord symbol parser;
  - shape generator invariants (playable span, one note per string, all required degrees present);
  - ChordScaleMatcher rankings for known cases (Dm7 in C → Dorian first; G7 in C → Mixolydian first; G7alt → Altered present).
- Analysis tests on a small set of reference audio clips with known BPM and chords. Track accuracy over time rather than requiring pass/fail.
- Snapshot or preview checks for the fretboard and keyboard renderers.

---

## Suggested order of work

1. ✅ **Hygiene and quick fixes:** gitignore `build/`, fix the formula bugs, the `% 7` crash and the per-marker recompute. Also fixed: favourites lost on search, and 9th/11th/13th chord tones not highlighting on the fretboard.
2. ✅ **SpotCore + theory model + tests** (0.1, 0.2). Built-ins ported to `SpotCore/Sources/SpotCore/Resources/BuiltInLibrary.json`; `ScaleType`/`ChordType` now read their formulas from it via `Appendix` (thin adapters, removed in step 3). Chord symbol parser and key-aware spelling done. Run tests with `swift test --package-path SpotCore`. Note: the 11 chord now includes the 9th; optional degrees live on `ChordDefinition` rather than `Formula`.
3. ✅ **State and persistence refactor** (0.4) + **instrument abstraction and `Marker` model** (0.3). `AppState` is replaced by `@Observable` stores in `Spot/State/` (`SelectionState`, `DisplaySettings`, `UIState`, `TransportState`, `LibraryStore`). Favourites are saved with SwiftData (`LibraryItemState`, keyed by definition id); display settings and sidebars are saved with UserDefaults, which suits simple preferences better than SwiftData. `Fretboard`, `Tuning`, `FretMarker` and the ported 3NPS positions are in SpotCore. The old enums, services and `Appendix` adapters are gone. Also fixed: 3NPS shapes for modes were shifted from the wrong root (A Dorian showed A major notes). The keyboard view is still deferred to step 11.
4. **Library v2:** shapes model, generators (3NPS/CAGED/voicings), detail panel, editors, import/export (Tab 1).
   - ✅ 4a. Shape model (`Shape`, `ShapeNote`, root-relative, fingers suggested per placement) and generators: N-notes-per-string for any scale and tuning (3NPS for 7-note scales, the 5 pentatonic boxes) and chord voicings for any chord/tuning (Open, Barre, Triad, Close, Drop 2, Drop 3, Shell, Other; inversion and string-set labels). Previous/next shape (⌘[ / ⌘]) replaces ⌘1–7; finger labels added to the label cycle (⌘L).
   - ✅ 4b. CAGED positions for scales (anchored on the five movable major chord forms, with stretches so no note is skipped) and CAGED arpeggio shapes for chords; shape type picker in the detail panel; sidebar filters (everything / favourites / scales / chords / intervals, scale families, sort); chords on each scale degree (triads or sevenths, Roman numerals) in `IntervalMatrixView`, clickable, with a way back to the scale. Added the augmented major 7th chord.
   - ✅ 4c. Built-in library grown to 58 scales and 64 chords (harmonic major modes, pentatonic modes, Japanese pentatonics, bebop, symmetric, Hungarian/Neapolitan/Persian/Enigmatic and more; add9, sus, altered dominants, quartal...). `SpotCore/Scripts/check_library.py` cross-checks every formula against tonal's dictionaries (52/58 scales and 59/64 chords matched by name, 0 errors; two documented differences for 7b5#9/7b5b9). Run it with `--missing` to see tonal entries Spot lacks.
   - ✅ 4d. Your own scales and chords (new, edit, duplicate any built-in to edit, delete) via a definition editor with live validation; shapes drawn on the fretboard (click to add/remove notes, right-click for fingers; new, copy, edit, delete); tags with a sidebar filter; source filter (built-in / mine / each imported bundle). Saved with SwiftData (`UserDefinition`, `UserShape`, as `.spotlib` JSON). `.spotlib` import (review sheet with skip / replace / keep both, also opens from Finder) and export (mine / by tag / everything). Format now carries shapes and tunings.
   - Follow-up: add an app test target. The library store and shape drawing logic were verified with a temporary self-check, not a permanent test.
5. ✅ **Audio engine core:** `TransportState` is a host-time clock (count-in, tempo changes keep position). `PlaybackController` sends MIDI (virtual "Spot" source + optional destination/channel, `SpotCore.MIDIOutput`) and schedules metronome clicks (`SpotCore.ClickPlayer`, AVAudioEngine) with a 100 ms lookahead so nothing is sent early. Shape preview (▶ / ⌘↩: chords strummed, scales up and down in eighths), ⌥-click a note, Play/Stop (⌘P), metronome (⇧⌘M), bar.beat display, Settings tab for MIDI and metronome. Verified with a MIDI loopback test and a temporary in-app timing check.
6. ✅ **Chord Practice** (Tab 2): `SpotCore.ChordScaleMatcher` ranks scales (commonness, avoid notes, fit to key, notes changed from the previous chord) and works out each note's role (chord tone / tension / avoid / outside); arpeggios (chord, guide tones, upper structures without avoid notes); key detection; the scale or arpeggio shape nearest the voicing. Tab: progression field with chord chips (⇧⌘[ / ⇧⌘]), key menu (auto or chosen), ranked scale and arpeggio lists with reasons, voicing stepping (⌘[ / ⌘]) and type filter, whole-neck toggle, colour by role or interval, 12-note tone map, chord and scale/arpeggio previews. The Editor tab is gone; the fretboard view is now drawing-only, fed by Library and Practice adapters.
7. ✅ **Sequencer A:** `.spot` files (package with `sequence.json`; other files kept on save) opened inside the Sequence tab of the single main window (`SequenceSession`: New / Open / Open Recent with security-scoped bookmarks / Save / Save As, autosave a second after each change, last file reopened at launch, unsaved Untitled kept across restarts, asks before discarding it). `SpotCore.ChordSequence` (chords as symbols on a beat grid, sections, loop, key, backing style) and `Backing` (voice-led voicings; pad / strum / comp). Chord lane: click/shift-click bars (snap bar / half bar / beat), type a chord and press Return to set it and move on, pin a scale per chord, sections, loop selection. Playback over MIDI from the selection with count-in, looping and stop at the end. Visualisation A (lane scrolls past a playhead at 25%, Now/Next with countdown and beat dots) and B (next chord fades in on the fretboard, shared notes ringed, next 3rd/7th pulse). ⌘N/⌘O/⌘S/⇧⌘S are New/Open/Save/Save As sequence; play and tempo in the footer drive the sequence on its tab; New Scale/Chord moved to ⌥⌘N / ⌥⇧⌘N; Highlight All Shapes moved to ⌥⌘O. No undo yet in sequence windows.
8. ✅ **Sequencer B:** audio by reference (security-scoped bookmark, fingerprint, last path; Locate… with a warning if a relinked file is a different recording). Waveform drawn in beat time under the chord lane; warp markers (double-click a hit, drag it onto its beat, ⌥ for between beats). Signalsmith Stretch 1.4.0 (+ Linear 0.6.4, MIT) vendored in `SpotCore/Sources/CStretch` behind a C API; `WarpRenderer` renders the warped track offline in the background (~2.5 s per 30 s of stereo in debug; events land within 2 ms of their beat). Playback queues the render in one-beat slices (seamless across loops). Practice speed 50–100% slows audio (AVAudioUnitTimePitch) and backing together. Tap tempo, volume, mute. The audio reference and markers live in `sequence.json`, so Save As has nothing extra to copy yet.
9. ❌ **Removed in Oct 2026** (along with chord backing): **Sequencer C:** `SpotCore/Analysis` (Accelerate only): onset envelope + chroma; tempo by weighted autocorrelation with half/double candidates; Ellis DP beat tracking; bar 1 from bass hits + chord changes; chords by beat-synchronous chroma templates (maj, m, 7, maj7, m7, dim) with Viterbi smoothing favouring changes on downbeats; key by Krumhansl–Schmuckler. Runs in the background when audio loads (~0.2 s per 4 min in release, ~2 s in debug). Analysis bar: tempo alternatives, nudge bar 1, use key, Apply beat grid (tempo + a warp marker per bar), Add chords (replace all / only empty bars); heard beats shown as ticks on the waveform. Synthetic-audio tests: beats within 15 ms median, chord changes on the right beat. Real recordings will be less accurate, especially chords; correction is by typing over bars.
   - Since then: sequence playback is clicks + audio + takes only (no MIDI backing). The footer drives the open sequence: loop (the selection), key (root ‹ › and major/minor/auto), tempo (with audio, a practice speed: the recording's own tempo, which the grid follows, stays put), tap tempo and time signature. Chords are clips: move/resize with grid and magnetic snapping (⌥ for free). The lane has its own scroll/zoom (overview bar, trackpad swipe and pinch) and stays still while playing, with optional Follow Playhead.
   - Warping works like a clip in Live: the recording has its own (user-set) tempo and always at least one warp marker (where it sits on the grid; dragging it alone moves the whole recording). Between markers it's stretched; outside them it plays at its own tempo. It's rendered at its own tempo, which is a plain copy except for sections between markers, so there's no waiting; the sequence tempo is applied as it plays (AVAudioUnitTimePitch). Section tempos are shown on the waveform and as Original/Section → playing tempo in the top row (drag, type or tap). No tempo, beat or chord detection.
10. **Recording**, visualisation C, then extras (D/E/F, Core ML chords).
   - ✅ 10a. Visualisation C: "Follow hand" neck view picks each chord's scale position closest to the previous one (starting near a chosen fret; click a fret to move the hand), shows only that position (other chord tones faint), fades the next chord in within its position, and Now/Next says "Move up/down to fret N" when a change needs a shift. Visualisation D as a small chord box of the next chord in its position. Options in the sequence View menu.
   - Fixed: Chord Practice crashed when the progression became empty while editing; nested file panels meant Add Audio (and other Open/Save panels) never appeared — now one Open and one Save panel per window.
   - ✅ 10b. Recording: Record (footer) records the chosen input (Settings: device, latency offset) into the package's `takes/` folder while the sequence plays (count-in if stopped); a take is placed on the grid from its first sample's host time minus the reported input latency and the offset. Takes play back with the sequence (through loops, slowed to match practice speed), mute/delete from the takes row, and are copied by Save As. Unsaved sequences are saved first.
   - ✅ Transport: Play/Pause (resumes where it stopped, no count-in), Stop (back to the selection), Back to Start; space bar toggles play/pause except while typing.
   - ✅ Warping, Live-style: waveform draws only what's visible (also fixes it vanishing while playing), redraws live while dragging; double-click to add/remove markers; drag to stretch (snaps to 16ths, ⌥ free); ⇧-drag slides a marker along the audio; drag the waveform to grab a moment onto a beat; ⌘= / ⌘− zoom. Only the stretch between neighbouring markers is re-rendered (~0.02 s). Audio before bar 1 is rendered and plays during the count-in.
11. **Piano:** keyboard view, piano voicings and fingerings.
12. **Tab editor** (replaces Chord Practice; see Tab 2):
    - 12a. ✅ Remove Chord Practice. Tab model in SpotCore (`TabScore`, `MasterBar`, `TabTrack`, `TabBar`/`TabVoice`, `TabBeat`, `TabDuration` in ticks of 960 per quarter, `TabNote` with every v1 technique), `.spottab` format (JSON, `iko.spot.tab`) with tests, `TabSession` (New / Open / Recent / Save / Save As / autosave / Untitled draft / undo), the tab's launcher and an overview (title, artist, tempo, bars, tracks with tuning, capo and sound). File menu items act on the tab that's showing.
    - 12b. ✅ Tab rendering (`TabStaffView`): bars wrapped into lines that fill the width (each bar sized by its rhythm, stretched per line), one track at a time with a track picker, ⌘= / ⌘− spacing. Staff with TAB, fret numbers breaking the strings, x / (ghost, tied) / ⟨harmonic⟩, rests drawn as shapes, stems and beams under the staff grouped by beat (dotted quarter in compound time), dots, tuplet numbers; time signatures where they change, repeats with counts, 1st/2nd endings, section markers, tempo marks, chord names, bar numbers. Click to put the cursor on a string at a beat (or after the last); the fretboard shows that beat's notes. Details popover for title, artist, tempo, bars and tracks.
    - 12c. ✅ Editing (`TabEditing` in SpotCore, tested; keys in the Tab tab): 0–9 frets (two quick digits for 10–29), ← → beats (past a full bar into the next, adding bars at the end), ↑ ↓ strings, ⇧← ⇧→ select, − = note value, . dot, / triplet, R rest, L tie, I insert, ⌫ delete, ⌘C/X/V; undo/redo. Toolbar for the same, Bar popover (time signature until the next change, repeats, endings, marker, tempo, insert/delete bar), Beat popover (chord name, text, strum), Keys list, cursor position, and a warning (and red bar number) when a bar doesn't add up.
    - 12d. ✅ Techniques: keys (H hammer-on/pull-off, S / ⇧S slides, B bends, V vibrato, M palm mute, ⇧L let ring, X dead, G ghost, N harmonic, T tapping, A accent) and a Technique menu (exact bends, every slide and harmonic), applied to the note at the cursor or every note in the selection. Drawn Guitar Pro style: H/P arcs, slide lines, bend arrows with amounts and dashed releases, vibrato waves, T / > / harmonic types / strum marks, "let ring" and "P.M." runs; beats with techniques get more room.
    - 12e. ✅ Playback over MIDI with the metronome (repeats, endings, tempo changes, bends, slides, vibrato, let ring, palm mute, ghost/dead/accent velocities). Space plays from the start, ⌥Space from the cursor; the playing beat is highlighted and kept in view, and the fretboard shows it. The footer's tempo, tap and time signature edit the tab at the cursor's bar.
    - 12f. ✅ Guitar Pro 7/8 (`.gp`) import and export (zip + GPIF XML). Open… reads .gp as an Untitled tab (drum tracks skipped, with a notice); File ▸ Export as Guitar Pro… writes GP7, checked in Guitar Pro 8. Known gap: chord names don't show in Guitar Pro after export (they survive the round trip back into Spot).
    - 12g. ✅ Guitar Pro 3–5 (`.gp3` `.gp4` `.gp5`) import (binary). Checked against 91 files (alphaTab's GP3–5 test files and a real GP5): every one read to its last byte, and each survives export to GP7 and back. Grace notes and whammy bar aren't kept; bends with more than four points are simplified when exported to GP7.
    - 12h. Guitar Pro 6 (`.gpx`) import.
    - 12i. Linking a tab to a sequence.

---

## Open questions
None blocking. Revisit later:
- MIDI file export of the chord lane (for dropping a progression into a DAW).
- The SoundFont choice, when the internal sampler is added.
