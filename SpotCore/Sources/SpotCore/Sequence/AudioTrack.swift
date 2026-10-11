//
//  AudioTrack.swift
//  SpotCore
//

import Foundation

/// A link to an audio file that stays outside the `.spot` package.
public struct AudioReference: Hashable, Codable, Sendable {
    /// Security-scoped bookmark, so the file can be found again after it moves.
    public var bookmark: Data?
    public var lastKnownPath: String
    public var fileName: String
    public var duration: Double
    public var sampleRate: Double
    public var channelCount: Int
    /// Identifies the audio, to warn when a relinked file isn't the same recording.
    public var fingerprint: String
    /// A video file (its sound is the recording): shown with its frames, and played alongside.
    public var hasVideo: Bool

    public init(bookmark: Data?, lastKnownPath: String, fileName: String, duration: Double,
                sampleRate: Double, channelCount: Int, fingerprint: String, hasVideo: Bool = false) {
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.fileName = fileName
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fingerprint = fingerprint
        self.hasVideo = hasVideo
    }

    enum CodingKeys: String, CodingKey {
        case bookmark, lastKnownPath, fileName, duration, sampleRate, channelCount, fingerprint, hasVideo
    }

    /// Files from before videos have no `hasVideo`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        lastKnownPath = try container.decode(String.self, forKey: .lastKnownPath)
        fileName = try container.decode(String.self, forKey: .fileName)
        duration = try container.decode(Double.self, forKey: .duration)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        channelCount = try container.decode(Int.self, forKey: .channelCount)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        hasVideo = try container.decodeIfPresent(Bool.self, forKey: .hasVideo) ?? false
    }
}

/// Pins a moment in the recording (seconds from its start) to a beat on the grid.
public struct WarpMarker: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceTime: Double
    public var beat: Double

    public init(id: UUID = UUID(), sourceTime: Double, beat: Double) {
        self.id = id
        self.sourceTime = sourceTime
        self.beat = beat
    }
}

/// The sequence's audio: which file, how it lines up with the grid, and its level.
///
/// Like a warped clip in Live: the recording has its own tempo, and warp markers pin moments in it to
/// beats. There's always at least one marker (where the recording sits on the grid); between markers
/// the audio is stretched to fit, and outside them it plays at its own tempo. The sequence's tempo is
/// separate: the whole thing is sped up or slowed down to it as it plays.
public struct AudioTrack: Hashable, Codable, Sendable {
    public var reference: AudioReference
    /// The tempo the recording was played at (the user sets it; nothing is detected).
    public var tempo: Double
    /// Kept sorted by beat, with source times rising. Never empty.
    public private(set) var warpMarkers: [WarpMarker]
    /// Decibels.
    public var gain: Double
    public var isMuted: Bool

    /// With no markers given, the start of the recording sits on bar 1.
    public init(reference: AudioReference, tempo: Double, warpMarkers: [WarpMarker] = [], gain: Double = 0, isMuted: Bool = false) {
        self.reference = reference
        self.tempo = tempo
        self.warpMarkers = warpMarkers.isEmpty ? [WarpMarker(sourceTime: 0, beat: 0)] : warpMarkers.sorted { $0.beat < $1.beat }
        self.gain = gain
        self.isMuted = isMuted
    }

    /// Beats against seconds in the recording.
    public var map: WarpMap {
        WarpMap(markers: warpMarkers, tempo: tempo)
    }

    /// The recording's own tempo at a beat: between two markers, what fits that stretch of audio onto
    /// those beats; outside them, `tempo`.
    public func segmentTempo(atBeat beat: Double) -> Double {
        guard let (a, b) = segment(atBeat: beat) else { return tempo }
        return (b.beat - a.beat) / (b.sourceTime - a.sourceTime) * 60
    }

    /// Sets the recording's tempo at a beat. Between two markers, the later one moves (and the markers
    /// after it with it, so their stretches keep their tempos); outside them, it sets `tempo`.
    public mutating func setSegmentTempo(_ bpm: Double, atBeat beat: Double) {
        let bpm = min(max(bpm, 20), 400)
        guard let (a, b) = segment(atBeat: beat) else {
            tempo = bpm
            return
        }
        let shift = a.beat + (b.sourceTime - a.sourceTime) * bpm / 60 - b.beat
        warpMarkers = warpMarkers.map { marker in
            var marker = marker
            if marker.beat >= b.beat { marker.beat += shift }
            return marker
        }
    }

    /// The markers either side of `beat`, if it's between two.
    private func segment(atBeat beat: Double) -> (WarpMarker, WarpMarker)? {
        guard let next = warpMarkers.firstIndex(where: { $0.beat > beat }), next > 0 else { return nil }
        return (warpMarkers[next - 1], warpMarkers[next])
    }

    /// Adds a marker, replacing any on the same beat. Returns false if it would make the audio run backwards.
    @discardableResult
    public mutating func setMarker(_ marker: WarpMarker) -> Bool {
        var markers = warpMarkers.filter { $0.id != marker.id && abs($0.beat - marker.beat) > 0.001 }
        markers.append(marker)
        markers.sort { $0.beat < $1.beat }
        guard WarpMap.isValid(markers) else { return false }
        warpMarkers = markers
        return true
    }

    /// Removes a marker, unless it's the only one.
    public mutating func removeMarker(_ id: UUID) {
        guard warpMarkers.count > 1 else { return }
        warpMarkers.removeAll { $0.id == id }
    }

    /// The recording's tempo over a stretch of beats, as it's warped now: how many beats it takes per minute of
    /// the recording there. Nil for an empty stretch.
    public func warpedTempo(over range: BeatRange) -> Double? {
        let seconds = map.sourceTime(atBeat: range.end) - map.sourceTime(atBeat: range.start)
        guard range.length > 0, seconds > 1e-6 else { return nil }
        return range.length / seconds * 60
    }

    /// The tempo of the stretch just before a marker (from the marker before it), if there is one.
    public func tempoBefore(_ markerId: UUID) -> Double? {
        guard let index = warpMarkers.firstIndex(where: { $0.id == markerId }), index > 0 else { return nil }
        return warpedTempo(over: BeatRange(warpMarkers[index - 1].beat, warpMarkers[index].beat))
    }

    /// Warp From Here, as in Live: from a marker on, the recording keeps going at `bpm` (beats per minute of the
    /// recording) to its end. The markers after it go, and one at the recording's end holds that tempo.
    public mutating func warpStraight(from markerId: UUID, bpm: Double) {
        guard let index = warpMarkers.firstIndex(where: { $0.id == markerId }), bpm > 0 else { return }
        let marker = warpMarkers[index]
        var markers = Array(warpMarkers.prefix(through: index))
        let remaining = reference.duration - marker.sourceTime
        if remaining > 0.01 {
            markers.append(WarpMarker(sourceTime: reference.duration, beat: marker.beat + remaining * bpm / 60))
        }
        warpMarkers = markers
    }

    /// Back to just the first marker: the recording where it starts, at its own tempo.
    public mutating func removeAllMarkers() {
        warpMarkers = Array(warpMarkers.prefix(1))
    }

    enum CodingKeys: String, CodingKey {
        case reference, tempo, warpMarkers, gain, isMuted
    }

    /// Files from before recordings had their own tempo have none (0): `ChordSequence` fills it in.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(AudioReference.self, forKey: .reference)
        tempo = try container.decodeIfPresent(Double.self, forKey: .tempo) ?? 0
        let markers = try container.decodeIfPresent([WarpMarker].self, forKey: .warpMarkers) ?? []
        // No markers used to mean the start of the recording on bar 1
        warpMarkers = markers.isEmpty ? [WarpMarker(sourceTime: 0, beat: 0)] : markers.sorted { $0.beat < $1.beat }
        gain = try container.decodeIfPresent(Double.self, forKey: .gain) ?? 0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }
}

/// Converts between beats and seconds in the recording, following the warp markers.
///
/// `tempo` is the recording's own. With no markers it starts on beat 1; one marker shifts it.
/// Between markers time is stretched evenly. Beyond the outermost markers the audio isn't stretched:
/// it plays at its own tempo, just moved along with the marker.
public struct WarpMap: Sendable {
    public let markers: [WarpMarker]
    public let tempo: Double

    public init(markers: [WarpMarker], tempo: Double) {
        self.markers = markers.sorted { $0.beat < $1.beat }
        self.tempo = tempo
    }

    static func isValid(_ markers: [WarpMarker]) -> Bool {
        zip(markers, markers.dropFirst()).allSatisfy { $0.beat < $1.beat && $0.sourceTime < $1.sourceTime }
    }

    private var secondsPerBeat: Double {
        60 / tempo
    }

    public func sourceTime(atBeat beat: Double) -> Double {
        switch markers.count {
        case 0:
            return beat * secondsPerBeat
        case 1:
            return markers[0].sourceTime + (beat - markers[0].beat) * secondsPerBeat
        default:
            if beat <= markers.first!.beat {
                return markers.first!.sourceTime + (beat - markers.first!.beat) * secondsPerBeat
            }
            if beat >= markers.last!.beat {
                return markers.last!.sourceTime + (beat - markers.last!.beat) * secondsPerBeat
            }
            let (a, b) = segment(where: { beat < $0.beat })
            let slope = (b.sourceTime - a.sourceTime) / (b.beat - a.beat)
            return a.sourceTime + (beat - a.beat) * slope
        }
    }

    public func beat(atSourceTime time: Double) -> Double {
        switch markers.count {
        case 0:
            return time / secondsPerBeat
        case 1:
            return markers[0].beat + (time - markers[0].sourceTime) / secondsPerBeat
        default:
            if time <= markers.first!.sourceTime {
                return markers.first!.beat + (time - markers.first!.sourceTime) / secondsPerBeat
            }
            if time >= markers.last!.sourceTime {
                return markers.last!.beat + (time - markers.last!.sourceTime) / secondsPerBeat
            }
            let (a, b) = segment(where: { time < $0.sourceTime })
            let slope = (b.beat - a.beat) / (b.sourceTime - a.sourceTime)
            return a.beat + (time - a.sourceTime) * slope
        }
    }

    /// The pair of markers either side of a point between the first and last marker.
    private func segment(where isBefore: (WarpMarker) -> Bool) -> (WarpMarker, WarpMarker) {
        let next = markers.firstIndex(where: isBefore) ?? markers.count
        let upper = min(max(next, 1), markers.count - 1)
        return (markers[upper - 1], markers[upper])
    }

    /// The recording's speed at a beat, relative to its own tempo (2 means it's stretched to half speed).
    public func stretch(atBeat beat: Double) -> Double {
        let delta = 0.01
        let seconds = sourceTime(atBeat: beat + delta) - sourceTime(atBeat: beat)
        return (delta * secondsPerBeat) / max(seconds, 1e-9)
    }
}

/// Something you recorded over the sequence, saved in the package's `takes` folder.
public struct RecordedTake: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// File name inside the package's `takes` folder.
    public var fileName: String
    /// Where the first sample lands on the grid.
    public var startBeat: Double
    /// Seconds.
    public var duration: Double
    /// The tempo it was played at (including practice speed), to play back in time at other speeds.
    public var tempo: Double
    public var isMuted: Bool
    /// Decibels.
    public var gain: Double

    public init(id: UUID = UUID(), name: String, fileName: String, startBeat: Double, duration: Double, tempo: Double,
                isMuted: Bool = false, gain: Double = 0) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.startBeat = startBeat
        self.duration = duration
        self.tempo = tempo
        self.isMuted = isMuted
        self.gain = gain
    }

    public var endBeat: Double {
        startBeat + duration * tempo / 60
    }

    /// Seconds into the take that line up with `beat`.
    public func offset(atBeat beat: Double) -> Double {
        (beat - startBeat) * 60 / tempo
    }
}
