//
//  ChordPattern.swift
//  SpotCore
//

import Foundation

/// A run of chords that repeats, like a looped clip in Live: grouped once (⌘G), then stretched to repeat, and
/// placed again later in the song as linked instances (editing any of them edits them all). Named, it marks a part
/// of the song ("Verse").
public struct ChordPattern: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// One time round, in beats.
    public var length: Double
    /// Within one time round: ranges from 0 to `length`, sorted and not overlapping.
    public var chords: [ChordRegion]

    public init(id: UUID = UUID(), name: String = "", length: Double, chords: [ChordRegion] = []) {
        self.id = id
        self.name = name
        self.length = max(length, 0.0625)
        self.chords = chords.sorted { $0.range.start < $1.range.start }
    }
}

/// Where a pattern is in the song. Longer than the pattern, it repeats; shorter, it stops part way.
public struct PatternInstance: Identifiable, Hashable, Codable, Sendable, BeatRanged {
    public var id: UUID
    public var patternId: UUID
    public var range: BeatRange
    /// How far into the pattern it starts (beats), if its start has been trimmed.
    public var phase: Double

    public init(id: UUID = UUID(), patternId: UUID, range: BeatRange, phase: Double = 0) {
        self.id = id
        self.patternId = patternId
        self.range = range
        self.phase = phase
    }
}

/// Where one of the song's chords comes from, when it's in a pattern.
public struct ChordSource: Hashable, Sendable {
    public var instanceId: UUID
    public var patternId: UUID
    /// The pattern's chord.
    public var chordId: UUID
    /// The beat this time round starts on (the pattern's 0).
    public var roundStart: Double
    /// Which time round (0 the first).
    public var round: Int
}

extension ChordSequence {
    // MARK: Reading

    /// The pattern instance at a beat, and its pattern.
    public func patternInstance(at beat: Double) -> (instance: PatternInstance, pattern: ChordPattern)? {
        guard let instance = instances.first(where: { $0.range.contains(beat) }),
              let pattern = pattern(instance.patternId) else { return nil }
        return (instance, pattern)
    }

    public func pattern(_ id: UUID) -> ChordPattern? {
        patterns.first { $0.id == id }
    }

    /// How many places a pattern is used.
    public func uses(of patternId: UUID) -> Int {
        instances.filter { $0.patternId == patternId }.count
    }

    /// The name of the part of the song at a beat (its pattern's), if it has one.
    public func partName(at beat: Double) -> String? {
        patternInstance(at: beat).map(\.pattern.name).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Patterns

    /// Groups the chords in `range` into a new pattern exactly `range` long (⌘G). Chords crossing its edges are cut
    /// there. Not over another pattern. Returns the new instance's id.
    @discardableResult
    public mutating func makePattern(from range: BeatRange, name: String = "") -> UUID? {
        let range = BeatRange(max(0, range.start), min(lengthInBeats, range.end))
        guard range.length > 0, !instances.contains(where: { $0.range.overlaps(range) }) else { return nil }
        let inside = looseChords.compactMap { chord -> ChordRegion? in
            let start = max(chord.range.start, range.start), end = min(chord.range.end, range.end)
            guard end > start else { return nil }
            var copy = chord
            copy.id = UUID()
            copy.range = BeatRange(start - range.start, end - range.start)
            return copy
        }
        let pattern = ChordPattern(name: name, length: range.length, chords: inside)
        let instance = PatternInstance(patternId: pattern.id, range: range)
        editAll {
            $0.looseChords = ChordSequence.carve($0.looseChords, removing: range)
            $0.patterns.append(pattern)
            $0.instances.append(instance)
            $0.instances.sort { $0.range.start < $1.range.start }
        }
        return instance.id
    }

    /// Back to plain chords where it is (⇧⌘G), repeats and all. The pattern goes if nothing else uses it.
    public mutating func ungroup(_ instanceId: UUID) {
        guard let instance = instances.first(where: { $0.id == instanceId }) else { return }
        let laidOut = chords.filter { chordSources[$0.id]?.instanceId == instanceId }.map { chord -> ChordRegion in
            var copy = chord
            copy.id = UUID()
            return copy
        }
        editAll {
            $0.instances.removeAll { $0.id == instanceId }
            if $0.uses(of: instance.patternId) == 0 {
                $0.patterns.removeAll { $0.id == instance.patternId }
            }
            $0.looseChords = ChordSequence.carve($0.looseChords, removing: instance.range) + laidOut
            $0.looseChords.sort { $0.range.start < $1.range.start }
        }
    }

    /// Takes a pattern out of the sequence where it's used here, chords and all (other places it's used keep it).
    public mutating func removeInstance(_ instanceId: UUID) {
        guard let instance = instances.first(where: { $0.id == instanceId }) else { return }
        editAll {
            $0.instances.removeAll { $0.id == instanceId }
            if $0.uses(of: instance.patternId) == 0 {
                $0.patterns.removeAll { $0.id == instance.patternId }
            }
        }
    }

    /// Moves or stretches an instance (its edges dragged): longer repeats the pattern, the start trimmed starts
    /// part way into it. It covers plain chords under it, and stops short of other patterns.
    public mutating func setRange(of instanceId: UUID, to newRange: BeatRange, moving: Bool = false) {
        guard let index = instances.firstIndex(where: { $0.id == instanceId }),
              let pattern = pattern(instances[index].patternId) else { return }
        var instance = instances[index]
        var range = BeatRange(max(0, newRange.start), min(lengthInBeats, newRange.end))
        // Not over its neighbours
        let others = instances.filter { $0.id != instanceId }
        if let before = others.last(where: { $0.range.start < instance.range.start }), range.start < before.range.end {
            if moving { range = BeatRange(before.range.end, before.range.end + range.length) } else { range.start = before.range.end }
        }
        if let after = others.first(where: { $0.range.start >= instance.range.end - 1e-9 }), range.end > after.range.start {
            if moving { range = BeatRange(after.range.start - range.length, after.range.start) } else { range.end = after.range.start }
        }
        guard range.length >= 0.0625 else { return }
        if !moving {
            // Trimming the start moves where in the pattern it begins
            let delta = range.start - instance.range.start
            instance.phase = (instance.phase + delta).truncatingRemainder(dividingBy: pattern.length)
            if instance.phase < 0 { instance.phase += pattern.length }
        }
        instance.range = range
        editAll {
            $0.instances[index] = instance
            $0.looseChords = ChordSequence.carve($0.looseChords, removing: range)
        }
    }

    /// Another instance of the same pattern straight after this one, as long (⌘D). It covers what's there: plain
    /// chords, and the start of a pattern it runs into. Returns the new instance's id.
    @discardableResult
    public mutating func duplicate(_ instanceId: UUID) -> UUID? {
        guard let instance = instances.first(where: { $0.id == instanceId }) else { return nil }
        let range = BeatRange(instance.range.end, min(lengthInBeats, instance.range.end + instance.range.length))
        if range.end >= lengthInBeats - 1e-9 && range.length < instance.range.length - 1e-9 {
            // Make room at the end of the song
            setLength(bars: Int(ceil((instance.range.end + instance.range.length) / barLength - 1e-9)))
            return duplicate(instanceId)
        }
        guard range.length > 0 else { return nil }
        let copy = PatternInstance(patternId: instance.patternId, range: range, phase: instance.phase)
        let lengths = Dictionary(patterns.map { ($0.id, $0.length) }, uniquingKeysWith: { first, _ in first })
        editAll { sequence in
            sequence.looseChords = ChordSequence.carve(sequence.looseChords, removing: range)
            sequence.instances = sequence.instances.compactMap { other in
                guard other.range.overlaps(range), other.id != instanceId else { return other }
                // Trim the part it covers off the front (or drop it if it's all covered)
                guard other.range.end > range.end, let length = lengths[other.patternId] else { return nil }
                var trimmed = other
                let delta = range.end - other.range.start
                trimmed.range = BeatRange(range.end, other.range.end)
                trimmed.phase = (other.phase + delta).truncatingRemainder(dividingBy: length)
                return trimmed
            }
            sequence.instances.append(copy)
            sequence.instances.sort { $0.range.start < $1.range.start }
            let used = Set(sequence.instances.map(\.patternId))
            sequence.patterns.removeAll { !used.contains($0.id) }
        }
        return copy.id
    }

    /// This instance gets its own copy of the pattern, to change without changing the others.
    public mutating func makeUnique(_ instanceId: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == instanceId }),
              let pattern = pattern(instances[index].patternId), uses(of: pattern.id) > 1 else { return }
        var copy = pattern
        copy.id = UUID()
        copy.chords = pattern.chords.map { chord in
            var chord = chord
            chord.id = UUID()
            return chord
        }
        editAll {
            $0.patterns.append(copy)
            $0.instances[index].patternId = copy.id
        }
    }

    public mutating func rename(pattern patternId: UUID, to name: String) {
        guard let index = patterns.firstIndex(where: { $0.id == patternId }) else { return }
        patterns[index].name = name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Laying it out

    /// A chord in a pattern, as it comes round in an instance: the same id every time it's worked out, so the
    /// analysis and the selection can hold on to it.
    static func laidOutId(instance: UUID, round: Int, chord: UUID) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: instance.uuid) { a in
            withUnsafeBytes(of: chord.uuid) { b in
                for index in 0..<16 { bytes[index] = a[index] ^ b[index] }
            }
        }
        withUnsafeBytes(of: UInt32(truncatingIfNeeded: round + 1).bigEndian) { r in
            for index in 0..<4 { bytes[index] ^= r[index] }
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40    // a valid version 4 UUID
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The song's chords: the plain ones, and each instance's pattern laid out round after round.
    static func layOut(loose: [ChordRegion], patterns: [ChordPattern], instances: [PatternInstance])
        -> (chords: [ChordRegion], sources: [UUID: ChordSource]) {
        var chords = loose
        var sources: [UUID: ChordSource] = [:]
        let byId = Dictionary(patterns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for instance in instances {
            guard let pattern = byId[instance.patternId], pattern.length > 0 else { continue }
            var roundStart = instance.range.start - instance.phase
            var round = 0
            while roundStart < instance.range.end - 1e-9 && round < 10_000 {
                for chord in pattern.chords {
                    let start = max(roundStart + chord.range.start, instance.range.start)
                    let end = min(roundStart + chord.range.end, instance.range.end)
                    guard end - start > 1e-9 else { continue }
                    var placed = chord
                    placed.id = laidOutId(instance: instance.id, round: round, chord: chord.id)
                    placed.range = BeatRange(start, end)
                    chords.append(placed)
                    sources[placed.id] = ChordSource(instanceId: instance.id, patternId: pattern.id, chordId: chord.id,
                                                     roundStart: roundStart, round: round)
                }
                roundStart += pattern.length
                round += 1
            }
        }
        chords.sort { $0.range.start < $1.range.start }
        return (chords, sources)
    }

    // MARK: Editing chords in patterns

    /// Changes a pattern's chord (by its id there).
    mutating func editPatternChord(_ patternId: UUID, _ chordId: UUID, _ change: (inout ChordRegion) -> Void) {
        guard let p = patterns.firstIndex(where: { $0.id == patternId }),
              let c = patterns[p].chords.firstIndex(where: { $0.id == chordId }) else { return }
        change(&patterns[p].chords[c])
    }

    /// Puts a chord into a pattern over `range` (within one time round), trimming what was there.
    mutating func setPatternChord(_ patternId: UUID, _ chord: ChordRegion) {
        guard let p = patterns.firstIndex(where: { $0.id == patternId }) else { return }
        var chord = chord
        chord.range = BeatRange(max(0, chord.range.start), min(patterns[p].length, chord.range.end))
        guard chord.range.length > 0 else { return }
        var chords = patterns[p].chords.filter { $0.id != chord.id }
        chords = ChordSequence.carve(chords, removing: chord.range)
        chords.append(chord)
        chords.sort { $0.range.start < $1.range.start }
        patterns[p].chords = chords
    }

    /// Takes `range` (within one time round) out of a pattern's chords.
    mutating func clearPatternChords(_ patternId: UUID, in range: BeatRange) {
        guard let p = patterns.firstIndex(where: { $0.id == patternId }) else { return }
        patterns[p].chords = ChordSequence.carve(patterns[p].chords, removing: range)
    }

    /// The time round of an instance a beat falls in: its start, and the instance's pattern.
    func round(at beat: Double) -> (instance: PatternInstance, pattern: ChordPattern, roundStart: Double)? {
        guard let (instance, pattern) = patternInstance(at: beat) else { return nil }
        let offset = beat - (instance.range.start - instance.phase)
        let round = floor(offset / pattern.length + 1e-9)
        return (instance, pattern, instance.range.start - instance.phase + round * pattern.length)
    }
}
