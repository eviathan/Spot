//
//  Zip.swift
//  SpotCore
//

import Foundation
import Compression

/// Just enough of the zip format for Guitar Pro 7/8 files: reading stored and deflated entries, and writing
/// deflated ones. No zip64, encryption or spanning.
enum Zip {
    enum Error: Swift.Error {
        case notAZip
        case damaged
        case unsupportedCompression(Int)
    }

    /// Every file in the archive, by its path ("Content/score.gpif"). Folders are left out.
    static func entries(of data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        // The end of central directory record: the last "PK\5\6", at least 22 bytes from the end
        guard bytes.count >= 22 else { throw Error.notAZip }
        var end = bytes.count - 22
        let earliest = max(0, bytes.count - 22 - 65_535)
        while end >= earliest, readUInt32(bytes, end) != 0x0605_4b50 {
            end -= 1
        }
        guard end >= earliest else { throw Error.notAZip }
        let count = Int(readUInt16(bytes, end + 10))
        var offset = Int(readUInt32(bytes, end + 16))

        var files: [String: Data] = [:]
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, readUInt32(bytes, offset) == 0x0201_4b50 else { throw Error.damaged }
            let method = Int(readUInt16(bytes, offset + 10))
            let compressedSize = Int(readUInt32(bytes, offset + 20))
            let size = Int(readUInt32(bytes, offset + 24))
            let nameLength = Int(readUInt16(bytes, offset + 28))
            let extraLength = Int(readUInt16(bytes, offset + 30))
            let commentLength = Int(readUInt16(bytes, offset + 32))
            let localOffset = Int(readUInt32(bytes, offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw Error.damaged }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength

            guard !name.hasSuffix("/") else { continue }
            // The local header's name and extra field can differ in length from the central directory's
            guard localOffset + 30 <= bytes.count, readUInt32(bytes, localOffset) == 0x0403_4b50 else { throw Error.damaged }
            let start = localOffset + 30 + Int(readUInt16(bytes, localOffset + 26)) + Int(readUInt16(bytes, localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw Error.damaged }
            let stored = Data(bytes[start..<(start + compressedSize)])
            switch method {
            case 0:
                files[name] = stored
            case 8:
                files[name] = try inflate(stored, size: size)
            default:
                throw Error.unsupportedCompression(method)
            }
        }
        return files
    }

    /// A zip of the files, in order, deflated (or stored where that's smaller).
    static func archive(_ files: [(path: String, data: Data)]) -> Data {
        var out = Data()
        var directory = Data()
        for file in files {
            let name = Array(file.path.utf8)
            let crc = crc32(file.data)
            let deflated = deflate(file.data)
            let (method, body): (UInt16, Data) = deflated.map { $0.count < file.data.count ? (8, $0) : (0, file.data) } ?? (0, file.data)
            let localOffset = UInt32(out.count)

            func header(central: Bool) -> Data {
                var h = Data()
                h.append(uint32: central ? 0x0201_4b50 : 0x0403_4b50)
                if central { h.append(uint16: 20) }              // made by
                h.append(uint16: 20)                             // needed to extract
                h.append(uint16: 0x0800)                         // UTF-8 names
                h.append(uint16: method)
                h.append(uint16: 0)                              // time
                h.append(uint16: 0x21)                           // date: 1 Jan 1980
                h.append(uint32: crc)
                h.append(uint32: UInt32(body.count))
                h.append(uint32: UInt32(file.data.count))
                h.append(uint16: UInt16(name.count))
                h.append(uint16: 0)                              // extra
                if central {
                    h.append(uint16: 0)                          // comment
                    h.append(uint16: 0)                          // disk
                    h.append(uint16: 0)                          // internal attributes
                    h.append(uint32: 0)                          // external attributes
                    h.append(uint32: localOffset)
                }
                h.append(contentsOf: name)
                return h
            }
            out.append(header(central: false))
            out.append(body)
            directory.append(header(central: true))
        }
        let directoryOffset = UInt32(out.count)
        out.append(directory)
        out.append(uint32: 0x0605_4b50)
        out.append(uint16: 0)
        out.append(uint16: 0)
        out.append(uint16: UInt16(files.count))
        out.append(uint16: UInt16(files.count))
        out.append(uint32: UInt32(directory.count))
        out.append(uint32: directoryOffset)
        out.append(uint16: 0)
        return out
    }

    // MARK: - Deflate (raw, as zip uses it: Compression's ZLIB is raw deflate without the zlib header)

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Error.damaged }
        return output
    }

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_encode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          input.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    // MARK: - CRC-32

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Little-endian numbers

    private static func readUInt16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        guard at + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        guard at + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}

extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func append(uint32 value: UInt32) {
        append(uint16: UInt16(value & 0xFFFF))
        append(uint16: UInt16(value >> 16))
    }
}
