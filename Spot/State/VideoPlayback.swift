//
//  VideoPlayback.swift
//  Spot
//

import AVFoundation
import AppKit
import Observation
import SpotCore

/// A sequence's video, when its recording is a video file: the picture, kept in step with the sequence, and frames
/// for the filmstrip.
///
/// The sound comes from the recording as Spot plays it (warped and at the sequence's tempo); the picture is a muted
/// player that follows. Through warp markers time doesn't run evenly, so it's steered rather than just started: a
/// few times a frame it's told where the recording should be and how fast it's going there, nudges its speed to
/// close small gaps and jumps over big ones. Stopped, it shows the frame at the playhead.
/// Used on the main thread.
@Observable
final class VideoPlayback {
    let player: AVPlayer
    let frames: VideoFrames
    /// Width over height, as shown.
    private(set) var aspectRatio: CGFloat = 16 / 9
    let duration: Double

    /// Where the recording should be (seconds) and how fast it's moving (seconds a second, 0 when stopped).
    @ObservationIgnored var target: (() -> (time: Double, speed: Double)?)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var lastSeek: Double = -1
    /// The speed it was last started at while playing, and when (host time).
    @ObservationIgnored private var syncedSpeed: Double?
    @ObservationIgnored private var lastSync: UInt64 = 0

    init(url: URL, duration: Double) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        // Speeds other than 1 (the sequence at a different tempo, stretches between markers) without pausing for it
        item.audioTimePitchAlgorithm = .varispeed
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        frames = VideoFrames(asset: asset)
        self.duration = duration

        Task { @MainActor [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return }
            let shown = size.applying(transform)
            guard abs(shown.height) > 0 else { return }
            self?.aspectRatio = abs(shown.width) / abs(shown.height)
            self?.frames.aspectRatio = abs(shown.width) / abs(shown.height)
        }

        // Steered on every screen refresh or so (in every run loop mode, so it keeps up during drags and resizes)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.steer()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func close() {
        timer?.invalidate()
        timer = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        frames.cancel()
    }

    private func steer() {
        guard let wanted = target?() else { return }
        let time = min(max(wanted.time, 0), max(0, duration - 0.01))
        let outside = wanted.time < 0 || wanted.time >= duration

        // Stopped (or the recording isn't playing here): just the frame
        if wanted.speed <= 0 || outside {
            syncedSpeed = nil
            if player.rate != 0 { player.rate = 0 }
            let current = player.currentTime().seconds
            if !isSeeking, abs(time - lastSeek) > 0.001, abs(current - time) > 0.5 / 60 {
                seek(to: time, exactly: true, thenRate: 0)
            }
            return
        }

        // Playing: started at an exact moment of the video at an exact time on the clock the sound is scheduled
        // by, so they stay together; done again when the speed changes (a warp marker, the tempo) or it's drifted
        let now = HostTime.now
        let settled = HostTime.seconds(from: lastSync, to: now) > 0.3
        let drift = abs(time - player.currentTime().seconds)
        let speedChanged = syncedSpeed.map { abs($0 - wanted.speed) > 0.002 } ?? true
        guard speedChanged || (settled && drift > 0.04) else { return }
        let lead = 0.05
        let start = HostTime.adding(lead, to: now)
        player.setRate(Float(wanted.speed), time: CMTime(seconds: min(time + wanted.speed * lead, duration), preferredTimescale: 6000),
                       atHostTime: CMClockMakeHostTimeFromSystemUnits(start))
        syncedSpeed = wanted.speed
        lastSync = now
    }

    private func seek(to time: Double, exactly: Bool, thenRate rate: Float) {
        isSeeking = true
        lastSeek = time
        let tolerance = exactly ? CMTime.zero : CMTime(seconds: 0.04, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSeeking = false
                if rate > 0 { self.player.rate = rate }
            }
        }
    }
}

/// Small frames of a video for the filmstrip, made in the background as they're asked for.
///
/// Asked for a moment at a spacing (the time between neighbouring frames on screen), it gives the nearest frame it
/// already has (or none yet), and makes the one at that moment, rounded to the spacing so scrolling and zooming
/// reuse them. `version` goes up as they arrive, for the filmstrip to redraw.
/// Used on the main thread.
@Observable
final class VideoFrames {
    private(set) var version = 0
    var aspectRatio: CGFloat = 16 / 9

    @ObservationIgnored private let generator: AVAssetImageGenerator
    /// By time in milliseconds, and those times in order (to find the nearest).
    @ObservationIgnored private var images: [Int: CGImage] = [:]
    @ObservationIgnored private var times: [Int] = []
    @ObservationIgnored private var wanted: [Int] = []
    @ObservationIgnored private var queued: Set<Int> = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var publishPending = false

    private static let limit = 1500

    init(asset: AVURLAsset) {
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
    }

    /// The frame to show for `time` (seconds), when frames are `spacing` seconds apart on screen.
    func image(at time: Double, spacing: Double) -> CGImage? {
        // Rounded to a step that's a power of two (in tenths of a second) near the spacing, so frames are shared
        let step = max(0.1, pow(2, floor(log2(max(spacing, 0.1) / 0.1))) * 0.1)
        let key = Int((max(0, time) / step).rounded() * step * 1000)
        if let image = images[key] { return image }
        request(key)
        return nearest(to: Int(time * 1000), within: Int(spacing * 1000))
    }

    func cancel() {
        worker?.cancel()
        worker = nil
        wanted.removeAll()
        queued.removeAll()
    }

    private func nearest(to millis: Int, within: Int) -> CGImage? {
        guard !times.isEmpty else { return nil }
        var low = 0, high = times.count
        while low < high {
            let middle = (low + high) / 2
            if times[middle] < millis { low = middle + 1 } else { high = middle }
        }
        let candidates = [low - 1, low].filter { times.indices.contains($0) }.map { times[$0] }
        guard let best = candidates.min(by: { abs($0 - millis) < abs($1 - millis) }), abs(best - millis) <= max(within, 1) else {
            return nil
        }
        return images[best]
    }

    private func request(_ key: Int) {
        guard !queued.contains(key) else { return }
        queued.insert(key)
        wanted.append(key)
        // The latest asked for first; ones asked for long ago (scrolled past) are dropped
        if wanted.count > 80 {
            let dropped = wanted.prefix(wanted.count - 80)
            dropped.forEach { queued.remove($0) }
            wanted.removeFirst(dropped.count)
        }
        startWorker()
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, let key = self.wanted.popLast() {
                let time = CMTime(value: CMTimeValue(key), timescale: 1000)
                let image = try? await self.generator.image(at: time).image
                guard !Task.isCancelled else { break }
                self.queued.remove(key)
                if let image { self.store(image, at: key) }
            }
            self?.worker = nil
        }
    }

    private func store(_ image: CGImage, at key: Int) {
        if images.count >= VideoFrames.limit {
            images.removeAll(keepingCapacity: true)
            times.removeAll(keepingCapacity: true)
        }
        images[key] = image
        let index = times.firstIndex { $0 > key } ?? times.count
        times.insert(key, at: index)
        // Redrawn a few times a second as frames arrive, not for every one
        guard !publishPending else { return }
        publishPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.publishPending = false
            self?.version += 1
        }
    }
}
