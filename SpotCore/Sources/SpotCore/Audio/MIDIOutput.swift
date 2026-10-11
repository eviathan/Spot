//
//  MIDIOutput.swift
//  SpotCore
//

import CoreMIDI

public struct MIDIDestination: Identifiable, Hashable, Sendable {
    public var id: MIDIUniqueID
    public var name: String
}

public struct MIDIError: Error, CustomStringConvertible {
    public var status: OSStatus
    public var action: String

    public var description: String {
        "MIDI error \(status) while trying to \(action)"
    }
}

/// Sends notes as MIDI: always from a virtual source other apps can listen to,
/// and optionally straight to one destination (a synth, interface or DAW input).
public final class MIDIOutput {
    public let name: String
    /// 0–15 (shown to people as 1–16).
    public var channel: UInt8 = 0
    /// Also play everything on this synth inside Spot (for when nothing's listening to the MIDI); nil for none.
    public var synth: SoftSynth?
    /// Also send directly here; nil to only use the virtual source.
    public var destinationID: MIDIUniqueID? {
        didSet { destination = destinationID.flatMap(MIDIOutput.endpoint(for:)) }
    }

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var port = MIDIPortRef()
    private var destination: MIDIEndpointRef?

    /// Creates the virtual source, which appears to other apps as `name`.
    public init(name: String = "Spot") throws {
        self.name = name
        try check(MIDIClientCreateWithBlock(name as CFString, &client) { _ in }, "create a MIDI client")
        try check(MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source), "create the \(name) MIDI source")
        try check(MIDIOutputPortCreate(client, "\(name) output" as CFString, &port), "create a MIDI output port")
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIPortDispose(port)
        MIDIClientDispose(client)
    }

    /// MIDI destinations currently available, e.g. "IAC Driver Bus 1" or an interface's output.
    public static func destinations() -> [MIDIDestination] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            var id = MIDIUniqueID()
            var name: Unmanaged<CFString>?
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id) == noErr,
                  MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
                  let name else {
                return nil
            }
            return MIDIDestination(id: id, name: name.takeRetainedValue() as String)
        }
    }

    /// The virtual source's unique id, so tests (and other code) can connect to it.
    public var sourceUniqueID: MIDIUniqueID {
        var id = MIDIUniqueID()
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id)
        return id
    }

    public func noteOn(_ note: Int, velocity: Int, at time: MIDITimeStamp = 0) {
        send(status: 0x90, note, velocity, at: time)
    }

    public func noteOff(_ note: Int, at time: MIDITimeStamp = 0) {
        send(status: 0x80, note, 0, at: time)
    }

    /// 14-bit, 8192 is no bend.
    public func pitchBend(_ value: Int, at time: MIDITimeStamp = 0) {
        let value = min(max(value, 0), 16383)
        send(status: 0xE0, value & 0x7F, value >> 7, at: time)
    }

    public func controlChange(_ number: Int, value: Int, at time: MIDITimeStamp = 0) {
        send(status: 0xB0, number, value, at: time)
    }

    public func programChange(_ program: Int, at time: MIDITimeStamp = 0) {
        send(status: 0xC0, program, 0, at: time)
    }

    /// Silences anything still sounding (All Notes Off) and drops events queued for the destination.
    public func allNotesOff() {
        if let destination {
            MIDIFlushOutput(destination)
        }
        send(status: 0xB0, 123, 0, at: 0)
        synth?.allNotesOff()
    }

    /// One MIDI 1.0 channel voice message as a Universal MIDI Packet word.
    static func word(status: UInt8, channel: UInt8, _ data1: Int, _ data2: Int) -> UInt32 {
        let messageType: UInt32 = 0x2  // MIDI 1.0 channel voice, group 0
        return messageType << 28
            | UInt32(status | (channel & 0x0F)) << 16
            | UInt32(clamp7(data1)) << 8
            | UInt32(clamp7(data2))
    }

    private static func clamp7(_ value: Int) -> UInt8 {
        UInt8(min(max(value, 0), 127))
    }

    private func send(status: UInt8, _ data1: Int, _ data2: Int, at time: MIDITimeStamp) {
        var word = MIDIOutput.word(status: status, channel: channel, data1, data2)
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, time, 1, &word)

        MIDIReceivedEventList(source, &list)
        if let destination {
            MIDISendEventList(port, destination, &list)
        }
        if let synth {
            // Program change is the one two-byte message sent here
            let bytes = status == 0xC0 ? [status | (channel & 0x0F), UInt8(min(max(data1, 0), 127))]
                                       : [status | (channel & 0x0F), UInt8(min(max(data1, 0), 127)), UInt8(min(max(data2, 0), 127))]
            synth.send(bytes, atHostTime: time)
        }
    }

    private static func endpoint(for id: MIDIUniqueID) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(id, &object, &type) == noErr, type == .destination else {
            return nil
        }
        return MIDIEndpointRef(object)
    }
}

private func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else {
        throw MIDIError(status: status, action: action)
    }
}
