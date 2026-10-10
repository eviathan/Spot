//
//  GPX.swift
//  SpotCore
//

import Foundation

/// Guitar Pro 6's container (`.gpx`): an optionally compressed ("BCFZ") little file system ("BCFS") of 4 KB
/// sectors, holding the score as GPIF XML (`score.gpif`) among other files.
enum GPX {
    enum Error: Swift.Error {
        case notGPX
        case damaged
    }

    /// The score's XML.
    static func score(in data: Data) throws -> Data {
        let files = try self.files(in: data)
        guard let score = files["score.gpif"] else { throw Error.damaged }
        return score
    }

    /// Every file in the container, by name.
    static func files(in data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw Error.notGPX }
        switch String(decoding: bytes[0..<4], as: UTF8.self) {
        case "BCFZ":
            // What it unpacks to starts with "BCFS"
            let unpacked = try decompress(Array(bytes[4...]))
            guard unpacked.count >= 4 else { throw Error.damaged }
            return fileSystem(Array(unpacked[4...]))
        case "BCFS":
            return fileSystem(Array(bytes[4...]))
        default:
            throw Error.notGPX
        }
    }

    // MARK: - Decompression

    /// LZ-style: a 4-byte length, then a bit stream of either raw bytes (flag 0, a 2-bit count, bits low first)
    /// or copies from what's already unpacked (flag 1, a 4-bit word size, then that many bits of offset back from
    /// the end and of length).
    static func decompress(_ bytes: [UInt8]) throws -> [UInt8] {
        var bits = BitReader(bytes: bytes)
        let expected = try bits.byte() | bits.byte() << 8 | bits.byte() << 16 | bits.byte() << 24
        guard expected >= 0, expected < 512 * 1024 * 1024 else { throw Error.damaged }
        var out: [UInt8] = []
        out.reserveCapacity(expected)
        do {
            while out.count < expected {
                if try bits.bits(1) == 1 {
                    let wordSize = try bits.bits(4)
                    let offset = try bits.bitsReversed(wordSize)
                    let size = try bits.bitsReversed(wordSize)
                    let start = out.count - offset
                    guard offset > 0, start >= 0 else { throw Error.damaged }
                    out.append(contentsOf: out[start..<(start + min(offset, size))])
                } else {
                    for _ in 0..<(try bits.bitsReversed(2)) {
                        out.append(UInt8(try bits.byte()))
                    }
                }
            }
        } catch is BitReader.End {
            // Some files stop short of the stated length; what's there is still good
        }
        return out
    }

    private struct BitReader {
        struct End: Swift.Error {}

        let bytes: [UInt8]
        var index = 0
        var bit = 8
        var current: UInt8 = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        /// The next bit, most significant first within each byte.
        mutating func next() throws -> Int {
            if bit >= 8 {
                guard index < bytes.count else { throw End() }
                current = bytes[index]
                index += 1
                bit = 0
            }
            defer { bit += 1 }
            return Int(current >> (7 - bit)) & 1
        }

        /// `count` bits, the first the most significant.
        mutating func bits(_ count: Int) throws -> Int {
            var value = 0
            for _ in 0..<count {
                value = value << 1 | (try next())
            }
            return value
        }

        /// `count` bits, the first the least significant.
        mutating func bitsReversed(_ count: Int) throws -> Int {
            var value = 0
            for shift in 0..<count {
                value |= (try next()) << shift
            }
            return value
        }

        mutating func byte() throws -> Int {
            try bits(8)
        }
    }

    // MARK: - File system

    /// Sectors of 4 KB; the first is empty. A file entry (type 2) has its name at 4 (zero-terminated, up to 127
    /// bytes), its size at 0x8C, and from 0x94 the numbers of the sectors holding it, ending with 0.
    private static func fileSystem(_ data: [UInt8]) -> [String: Data] {
        let sectorSize = 0x1000
        func int(_ at: Int) -> Int {
            guard at >= 0, at + 4 <= data.count else { return 0 }
            return Int(Int32(bitPattern: UInt32(data[at]) | UInt32(data[at + 1]) << 8 | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24))
        }

        var files: [String: Data] = [:]
        var offset = sectorSize
        while offset + 3 < data.count {
            if int(offset) == 2 {
                let nameBytes = data[(offset + 4)..<min(offset + 4 + 127, data.count)].prefix { $0 != 0 }
                let name = String(decoding: nameBytes, as: UTF8.self)
                let size = int(offset + 0x8C)
                var contents: [UInt8] = []
                var pointer = offset + 0x94
                while true {
                    let sector = int(pointer)
                    pointer += 4
                    guard sector > 0, sector * sectorSize < data.count else { break }
                    // The next entry comes after this file's last sector
                    offset = sector * sectorSize
                    contents += data[offset..<min(offset + sectorSize, data.count)]
                }
                files[name] = Data(contents.prefix(max(size, 0)))
            }
            offset += sectorSize
        }
        return files
    }
}
