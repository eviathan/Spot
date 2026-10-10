//
//  Recording.swift
//  SpotCore
//

import AVFoundation
import CoreAudio

/// An audio input on this Mac (built-in microphone, an interface...).
public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public var id: AudioDeviceID
    public var name: String
    public var channelCount: Int
}

public enum AudioDevices {
    /// Devices with at least one input channel.
    public static func inputs() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            let channels = inputChannelCount(id)
            guard channels > 0 else { return nil }
            return AudioInputDevice(id: id, name: name(of: id) ?? "Input \(id)", channelCount: channels)
        }
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}

/// Writes incoming buffers to a file and remembers when the first one was captured.
/// Separate from the input so it can be tested without a microphone.
public final class TakeWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let lock = NSLock()
    private var firstHostTime: UInt64?
    private var frames: AVAudioFramePosition = 0
    private var peak: Float = 0

    public init(url: URL, format: AVAudioFormat) throws {
        var settings = format.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMIsFloatKey] = true
        settings[AVLinearPCMBitDepthKey] = 32
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    public func write(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) throws {
        try file.write(from: buffer)
        var bufferPeak: Float = 0
        if let data = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for index in 0..<Int(buffer.frameLength) {
                    bufferPeak = max(bufferPeak, abs(data[channel][index]))
                }
            }
        }
        lock.lock()
        if firstHostTime == nil && time.isHostTimeValid {
            firstHostTime = time.hostTime
        }
        frames += AVAudioFramePosition(buffer.frameLength)
        peak = bufferPeak
        lock.unlock()
    }

    /// Host time of the first captured sample.
    public var startHostTime: UInt64? {
        lock.lock(); defer { lock.unlock() }
        return firstHostTime
    }

    public var duration: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(frames) / file.processingFormat.sampleRate
    }

    /// Loudest sample in the latest buffer, for a level meter.
    public var level: Float {
        lock.lock(); defer { lock.unlock() }
        return peak
    }
}

/// Records the chosen input to a file.
public final class InputRecorder {
    private let engine = AVAudioEngine()
    private var writer: TakeWriter?
    private var writeError: Error?

    public init() {}

    /// Seconds between sound reaching the input and its buffer's timestamp (device + safety offset).
    public var inputLatency: Double {
        engine.inputNode.presentationLatency
    }

    public var level: Float {
        writer?.level ?? 0
    }

    public var isRecording: Bool {
        writer != nil
    }

    /// Uses a particular device instead of the system default input. Only while not recording.
    public func setDevice(_ id: AudioDeviceID?) throws {
        guard let id, let unit = engine.inputNode.audioUnit else { return }
        var device = id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Couldn't use that input device"])
        }
    }

    /// Starts writing the input to `url`.
    public func start(writingTo url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "Spot", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio input is available. Check the input device in Settings and that Spot may use the microphone."])
        }
        let writer = try TakeWriter(url: url, format: format)
        self.writer = writer
        writeError = nil
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, time in
            do {
                try writer.write(buffer, at: time)
            } catch {
                self?.writeError = error
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.writer = nil
            throw error
        }
    }

    /// Stops and returns when the take started (host time of its first sample) and how long it is.
    public func stop() -> (startHostTime: UInt64, duration: Double)? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        defer { writer = nil }
        guard let writer, let start = writer.startHostTime, writer.duration > 0 else { return nil }
        return (start, writer.duration)
    }
}

/// Plays one recorded take at an exact time, optionally at a different speed (without changing pitch).
public final class TakePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let file: AVAudioFile

    public init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: file.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
    }

    public var duration: Double {
        Double(file.length) / file.processingFormat.sampleRate
    }

    /// Plays from `offset` seconds into the take, starting at `hostTime`, at `rate` (1 = as recorded).
    public func play(from offset: Double, atHostTime hostTime: UInt64, rate: Float, volume: Float) throws {
        player.stop()
        let start = AVAudioFramePosition(max(0, offset) * file.processingFormat.sampleRate)
        guard start < file.length else { return }
        if !engine.isRunning {
            try engine.start()
        }
        timePitch.rate = min(max(rate, 0.25), 2)
        player.volume = volume
        player.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
        player.play(at: AVAudioTime(hostTime: hostTime))
    }

    public func stop() {
        player.stop()
    }
}
