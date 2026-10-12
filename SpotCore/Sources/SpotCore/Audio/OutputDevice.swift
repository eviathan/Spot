//
//  OutputDevice.swift
//  SpotCore
//

import AVFoundation
import AudioToolbox
import CoreAudio
import os

/// The system's output device, and Spot's engines' outputs following it there when it changes.
public enum OutputDevice {
    private static let outputs = NSHashTable<EngineOutput>.weakObjects()
    private static var isListening = false

    /// The system's output device now.
    public static var current: AudioDeviceID? {
        var device = AudioDeviceID(0)
        let status = get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &device)
        return status == noErr && device != 0 ? device : nil
    }

    /// The rate a device runs at.
    static func sampleRate(of device: AudioDeviceID) -> Double? {
        var rate = Float64(0)
        return get(device, kAudioDevicePropertyNominalSampleRate, &rate) == noErr && rate > 0 ? rate : nil
    }

    private static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> OSStatus {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    }

    /// Moves `output` whenever the system's output changes (headphones plugged in, another output picked).
    static func follow(_ output: EngineOutput) {
        outputs.add(output)
        guard !isListening else { return }
        isListening = true
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            guard let device = current else { return }
            outputs.allObjects.forEach { $0.move(to: device) }
        }
    }
}

/// Plays an engine through an output-only audio unit on the output device itself, rather than through the engine's
/// own output.
///
/// The engine's own output, in an app that may record (Spot can, for takes), goes through an aggregate macOS makes
/// of the default output and the default input. Making it and taking it down reconfigures the Mac's built-in audio,
/// which pops on its speakers, in every app playing: whenever an engine starts, and when Spot quits. An output unit
/// of our own plays to the speakers alone. The engine renders in real-time manual mode, a buffer at a time, as the
/// output unit asks for it.
public final class EngineOutput {
    public let engine: AVAudioEngine
    public let sampleRate: Double
    /// When the buffer being rendered will be heard, for the engine's nodes to read while they render it (the
    /// engine's own timestamps have no host time in manual mode).
    public let renderTime = RenderTime()

    private static let maxFrames: AVAudioFrameCount = 4_096
    private let renderBlock: AVAudioEngineManualRenderingBlock
    private var unit: AudioUnit?
    private var isRunning = false
    /// The latest buffer's host time and engine sample time, for turning host times into the engine's.
    private let anchor = OSAllocatedUnfairLock<(host: UInt64, sample: AVAudioFramePosition)?>(initialState: nil)

    /// Call before attaching anything to `engine` (it goes into manual rendering mode).
    public init(engine: AVAudioEngine) throws {
        self.engine = engine
        sampleRate = OutputDevice.current.flatMap(OutputDevice.sampleRate(of:)) ?? 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw CocoaError(.featureUnsupported)
        }
        try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: Self.maxFrames)
        renderBlock = engine.manualRenderingBlock

        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw CocoaError(.featureUnsupported) }
        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance), "create the output")
        guard let instance else { throw CocoaError(.featureUnsupported) }
        unit = instance
        if let device = OutputDevice.current {
            try point(at: device)
        }
        var stream = format.streamDescription.pointee
        try check(AudioUnitSetProperty(instance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                       &stream, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set the output's format")
        var maxFrames = UInt32(Self.maxFrames)
        try check(AudioUnitSetProperty(instance, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                       &maxFrames, UInt32(MemoryLayout<UInt32>.size)), "set the output's buffer size")
        var callback = AURenderCallbackStruct(inputProc: renderEngineOutput, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(instance, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                       &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "connect the output")
        try check(AudioUnitInitialize(instance), "start the output")
        OutputDevice.follow(self)
    }

    deinit {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
    }

    /// Starts the engine and the sound.
    public func start() throws {
        if !engine.isRunning {
            try engine.start()
        }
        guard let unit, !isRunning else { return }
        try check(AudioOutputUnitStart(unit), "start the sound")
        isRunning = true
    }

    /// Stops the sound and the engine.
    public func stop() {
        if let unit, isRunning {
            AudioOutputUnitStop(unit)
        }
        isRunning = false
        engine.stop()
        anchor.withLock { $0 = nil }
    }

    /// The engine sample time a host time falls on (for an `AVAudioTime` to schedule a node with).
    public func sampleTime(forHostTime hostTime: UInt64) -> AVAudioFramePosition {
        // Before the first buffer: about a buffer from now
        let anchor = anchor.withLock { $0 } ?? (HostTime.adding(0.01, to: HostTime.now), engine.manualRenderingSampleTime)
        return anchor.sample + AVAudioFramePosition((HostTime.seconds(from: anchor.host, to: hostTime) * sampleRate).rounded())
    }

    /// Carries on on another device (the engine's format stays; the output unit converts to the device's rate).
    func move(to device: AudioDeviceID) {
        guard let unit else { return }
        let wasRunning = isRunning
        if wasRunning { AudioOutputUnitStop(unit) }
        AudioUnitUninitialize(unit)
        try? point(at: device)
        AudioUnitInitialize(unit)
        if wasRunning { AudioOutputUnitStart(unit) }
    }

    private func point(at device: AudioDeviceID) throws {
        guard let unit else { return }
        var device = device
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &device, UInt32(MemoryLayout<AudioDeviceID>.size)), "use the output device")
    }

    /// On the audio thread: one buffer of the engine.
    fileprivate func render(_ time: AudioTimeStamp, frames: UInt32, into data: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let hostTime = time.mFlags.contains(.hostTimeValid) ? time.mHostTime : HostTime.now
        renderTime.hostTime = hostTime
        let sample = engine.manualRenderingSampleTime
        anchor.withLockIfAvailable { $0 = (hostTime, sample) }
        var status = noErr
        let result = frames <= Self.maxFrames ? renderBlock(frames, data, &status) : .error
        if result != .success {
            // Stopped, or between graphs: silence
            for buffer in UnsafeMutableAudioBufferListPointer(data) {
                if let bytes = buffer.mData { memset(bytes, 0, Int(buffer.mDataByteSize)) }
            }
        }
        return noErr
    }

    private func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't \(action) (error \(status))"])
        }
    }
}

/// When the buffer an engine is rendering will be heard. Written by its output just before each buffer, read by
/// the engine's nodes as they render it (all on the audio thread).
public final class RenderTime: @unchecked Sendable {
    public fileprivate(set) var hostTime: UInt64 = 0
}

private func renderEngineOutput(_ refCon: UnsafeMutableRawPointer, _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                                _ time: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frames: UInt32,
                                _ data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    guard let data else { return noErr }
    return Unmanaged<EngineOutput>.fromOpaque(refCon).takeUnretainedValue().render(time.pointee, frames: frames, into: data)
}
