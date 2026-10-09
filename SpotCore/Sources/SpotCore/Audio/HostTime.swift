//
//  HostTime.swift
//  SpotCore
//

import Darwin

/// The system clock that CoreMIDI timestamps and AVAudioTime host times are measured in.
public enum HostTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static var now: UInt64 {
        mach_absolute_time()
    }

    public static func ticks(forSeconds seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000 * Double(timebase.denom) / Double(timebase.numer))
    }

    /// Seconds from `from` to `to`; negative if `to` is earlier.
    public static func seconds(from: UInt64, to: UInt64) -> Double {
        let ticks = to >= from ? Double(to - from) : -Double(from - to)
        return ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    /// `seconds` after (or, if negative, before) `time`.
    public static func adding(_ seconds: Double, to time: UInt64) -> UInt64 {
        seconds >= 0 ? time + ticks(forSeconds: seconds) : time - min(time, ticks(forSeconds: -seconds))
    }
}
