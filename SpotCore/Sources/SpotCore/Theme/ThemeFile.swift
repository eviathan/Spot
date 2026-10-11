//
//  ThemeFile.swift
//  SpotCore
//

import Foundation

/// A colour as red, green, blue and alpha, each 0…1.
public struct RGBA: Hashable, Sendable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Reads `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(r, g, b)` or `rgba(r, g, b, a)`: channels 0–255 (or percentages),
    /// alpha 0–1 (or a percentage).
    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            let channels = hex.count == 8
                ? [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
                : [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF, 0xFF]
            self.init(Double(channels[0]) / 255, Double(channels[1]) / 255, Double(channels[2]) / 255, Double(channels[3]) / 255)
            return
        }
        for (prefix, count) in [("rgba(", 4), ("rgb(", 3)] where text.hasPrefix(prefix) && text.hasSuffix(")") {
            let parts = text.dropFirst(prefix.count).dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == count else { return nil }
            var values: [Double] = []
            for (index, part) in parts.enumerated() {
                let isAlpha = index == 3
                if part.hasSuffix("%"), let percent = Double(part.dropLast()) {
                    values.append(percent / 100)
                } else if let number = Double(part) {
                    values.append(isAlpha ? number : number / 255)
                } else {
                    return nil
                }
            }
            guard values.allSatisfy({ (0...1).contains($0) }) else { return nil }
            self.init(values[0], values[1], values[2], count == 4 ? values[3] : 1)
            return
        }
        return nil
    }

    /// `#RRGGBB`, or `rgba(…)` when see-through.
    public var description: String {
        let byte = { (value: Double) in Int((value * 255).rounded()) }
        if alpha < 0.999 {
            return "rgba(\(byte(red)), \(byte(green)), \(byte(blue)), \(String(format: "%.2f", alpha)))"
        }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

/// A theme: a name and colours by key. Groups in the file become dotted keys ("fretboard.strings").
public struct ThemeDefinition: Hashable, Sendable {
    public var name: String
    public var colors: [String: RGBA]

    public init(name: String, colors: [String: RGBA]) {
        self.name = name
        self.colors = colors
    }
}

/// Reads and writes themes as YAML: `name:` and colours as `key: value`, in groups by indentation, with `#`
/// comments. (The plain subset of YAML themes need, not all of it.)
///
///     name: Midnight
///     interface:
///       page: "#1B2233"
///       divider: rgba(255, 255, 255, 0.07)
///     intervals:
///       m3: "#D14F53"
public enum ThemeFile {
    public struct Problem: LocalizedError, Equatable {
        public let line: Int
        public let message: String

        public var errorDescription: String? {
            "Line \(line): \(message)"
        }
    }

    public static func parse(_ text: String) throws -> ThemeDefinition {
        var name: String?
        var colors: [String: RGBA] = [:]
        // The groups the current line is inside, by indentation
        var groups: [(indent: Int, key: String)] = []

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = stripComment(rawLine)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if line.trimmingCharacters(in: .whitespaces) == "---" { continue }
            let indent = line.prefix { $0 == " " }.count
            if line.contains("\t") {
                throw Problem(line: lineNumber, message: "Use spaces to indent, not tabs")
            }
            let content = line.trimmingCharacters(in: .whitespaces)
            guard let colon = content.firstIndex(of: ":") else {
                throw Problem(line: lineNumber, message: "Expected “key: value”")
            }
            let key = unquote(String(content[..<colon]).trimmingCharacters(in: .whitespaces))
            let value = unquote(String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            guard !key.isEmpty else { throw Problem(line: lineNumber, message: "A key is missing") }

            while let last = groups.last, last.indent >= indent { groups.removeLast() }
            if value.isEmpty {
                groups.append((indent, key))
                continue
            }
            let path = (groups.map(\.key) + [key]).joined(separator: ".")
            if path == "name" {
                name = value
            } else if let color = RGBA(value) {
                colors[path] = color
            } else {
                throw Problem(line: lineNumber, message: "“\(value)” isn't a colour (use #RRGGBB, #RRGGBBAA, rgb(r, g, b) or rgba(r, g, b, a))")
            }
        }
        guard let name, !name.isEmpty else {
            throw Problem(line: 1, message: "The theme needs a name (“name: My Theme”)")
        }
        return ThemeDefinition(name: name, colors: colors)
    }

    /// The theme as YAML, grouped, in the order of `keys` (any others after).
    public static func write(_ theme: ThemeDefinition, keyOrder keys: [String] = [], comments: [String: String] = [:]) -> String {
        let ordered = keys.filter { theme.colors[$0] != nil } + theme.colors.keys.filter { !keys.contains($0) }.sorted()
        var lines = ["name: \(theme.name)"]
        var currentGroup: [String] = []
        for key in ordered {
            let parts = key.split(separator: ".").map(String.init)
            let group = Array(parts.dropLast())
            if group != currentGroup {
                // Open the groups from where this one parts from the last
                let shared = zip(group, currentGroup).prefix { $0 == $1 }.count
                if shared == 0 { lines.append("") }
                for (depth, part) in group.enumerated().dropFirst(shared) {
                    lines.append(String(repeating: "  ", count: depth) + "\(part):")
                }
                currentGroup = group
            }
            let value = theme.colors[key]!.description
            let quoted = value.hasPrefix("#") ? "\"\(value)\"" : value
            let comment = comments[key].map { "   # \($0)" } ?? ""
            lines.append(String(repeating: "  ", count: group.count) + "\(parts.last!): \(quoted)\(comment)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Everything before a `#` that starts a comment (not one inside quotes, as in "#FF0000").
    private static func stripComment(_ line: String) -> String {
        var inQuotes: Character?
        var previous: Character = " "
        for (offset, character) in line.enumerated() {
            if let quote = inQuotes {
                if character == quote { inQuotes = nil }
            } else if character == "\"" || character == "'" {
                inQuotes = character
            } else if character == "#" && (previous == " " || offset == 0) {
                // A comment, unless it's a colour right after "key: " (unquoted hex)
                let rest = line[line.index(line.startIndex, offsetBy: offset)...]
                let before = line[..<line.index(line.startIndex, offsetBy: offset)].trimmingCharacters(in: .whitespaces)
                if before.hasSuffix(":"), rest.dropFirst().prefix(while: { $0.isHexDigit }).count >= 3 {
                    previous = character
                    continue
                }
                return String(line[..<line.index(line.startIndex, offsetBy: offset)])
            }
            previous = character
        }
        return line
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast())
    }
}

/// The themes that come with Spot (YAML files in the package's resources), the default first.
public enum BuiltInThemes {
    /// File name (without .yaml) and the file's text, in the order they're offered.
    public static let order = ["default", "midnight", "monochrome", "colourblind-red-green", "colourblind-blue-yellow"]

    public static func text(_ name: String) -> String? {
        let url = Bundle.module.url(forResource: name, withExtension: "yaml")
            ?? Bundle.module.url(forResource: name, withExtension: "yaml", subdirectory: "Themes")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// Every built-in theme, by file name.
    public static func all() -> [(id: String, theme: ThemeDefinition)] {
        order.compactMap { name in
            text(name).flatMap { try? ThemeFile.parse($0) }.map { (name, $0) }
        }
    }

    /// The default theme: every colour there is, so other themes can leave any out.
    public static var defaultTheme: ThemeDefinition {
        text("default").flatMap { try? ThemeFile.parse($0) } ?? ThemeDefinition(name: "Default", colors: [:])
    }
}

extension ThemeFile {
    /// The keys in the order a file lists them, and each one's comment: for writing a theme out laid out like it.
    public static func layout(of text: String) -> (order: [String], comments: [String: String]) {
        var order: [String] = []
        var comments: [String: String] = [:]
        var groups: [(indent: Int, key: String)] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let indent = line.prefix { $0 == " " }.count
            let key = String(trimmed[..<colon])
            var rest = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            while let last = groups.last, last.indent >= indent { groups.removeLast() }
            if rest.isEmpty {
                groups.append((indent, key))
                continue
            }
            let path = (groups.map(\.key) + [key]).joined(separator: ".")
            guard path != "name" else { continue }
            order.append(path)
            if let hash = rest.range(of: "   # ") {
                comments[path] = String(rest[hash.upperBound...])
                rest = String(rest[..<hash.lowerBound])
            }
        }
        return (order, comments)
    }
}
