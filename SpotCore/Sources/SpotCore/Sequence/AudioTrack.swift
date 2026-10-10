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

    public init(bookmark: Data?, lastKnownPath: String, fileName: String, duration: Double,
                sampleRate: Double, channelCount: Int, fingerprint: String) {
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.fileName = fileName
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fingerprint = fingerprint
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
public struct AudioTrack: Hashable, Codable, Sendable {
    public var reference: AudioReference
    /// Kept sorted by beat, with source times rising.
    public private(set) var warpMarkers: [WarpMarker]
    /// Decibels.
    public var gain: Double
    public var isMuted: Bool

    public init(reference: AudioReference, warpMarkers: [WarpMarker] = [], gain: Double = 0, isMuted: Bool = false) {
        self.reference = reference
        self.warpMarkers = warpMarkers.sorted { $0.beat < $1.beat }
        self.gain = gain
        self.isMuted = isMuted
    }

    public func map(tempo: Double) -> WarpMap {
        WarpMap(markers: warpMarkers, tempo: tempo)
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

    public mutating func removeMarker(_ id: UUID) {
        warpMarkers.removeAll { $0.id == id }
    }

    public mutating func removeAllMarkers() {
        warpMarkers = []
    }
}

/// Converts between beats and seconds in the recording, following the warp markers.
///
/// With no markers the recording starts on beat 1 at the sequence tempo. One marker shifts it.
/// Between markers time is stretched evenly; beyond the outer ones, the nearest section's speed carries on.
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
            let (a, b) = segment(where: { time < $0.sourceTime })
            let slope = (b.beat - a.beat) / (b.sourceTime - a.sourceTime)
            return a.beat + (time - a.sourceTime) * slope
        }
    }

    /// The pair of markers to interpolate between: the section containing the point,
    /// or the first/last section when it's outside them.
    private func segment(where isBefore: (WarpMarker) -> Bool) -> (WarpMarker, WarpMarker) {
        let next = markers.firstIndex(where: isBefore) ?? markers.count
        let upper = min(max(next, 1), markers.count - 1)
        return (markers[upper - 1], markers[upper])
    }

    /// The recording's speed at a beat, relative to the sequence tempo (2 means it's stretched to half speed).
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
