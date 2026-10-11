import XCTest
@testable import SpotCore

final class ThemeFileTests: XCTestCase {
    func testColourFormats() throws {
        XCTAssertEqual(RGBA("#FF8000"), RGBA(1, 128.0 / 255, 0))
        XCTAssertEqual(RGBA("#f80"), RGBA(1, 136.0 / 255, 0))
        XCTAssertEqual(try XCTUnwrap(RGBA("#FF000080")).alpha, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(RGBA("rgb(255, 0, 51)"), RGBA(1, 0, 0.2))
        XCTAssertEqual(RGBA("rgba(255, 255, 255, 0.07)"), RGBA(1, 1, 1, 0.07))
        XCTAssertEqual(RGBA("rgba(100%, 0%, 50%, 50%)"), RGBA(1, 0, 0.5, 0.5))
        XCTAssertNil(RGBA("blue"))
        XCTAssertNil(RGBA("rgb(300, 0, 0)"))
        XCTAssertNil(RGBA("#12345"))
        XCTAssertEqual(RGBA(1, 0.5, 0).description, "#FF8000")
        XCTAssertEqual(RGBA(1, 1, 1, 0.07).description, "rgba(255, 255, 255, 0.07)")
    }

    func testParsesGroupsAndComments() throws {
        let theme = try ThemeFile.parse("""
        # A theme
        name: "Night Drive"
        interface:
          page: "#1B2233"      # behind everything
          divider: rgba(255, 255, 255, 0.07)
        fretboard:
          strings: #C8CCD8
        intervals:
          m3: '#D14F53'
        """)
        XCTAssertEqual(theme.name, "Night Drive")
        XCTAssertEqual(theme.colors["interface.page"], RGBA("#1B2233"))
        XCTAssertEqual(theme.colors["interface.divider"], RGBA(1, 1, 1, 0.07))
        XCTAssertEqual(theme.colors["fretboard.strings"], RGBA("#C8CCD8"))
        XCTAssertEqual(theme.colors["intervals.m3"], RGBA("#D14F53"))
        XCTAssertEqual(theme.colors.count, 4)
    }

    func testProblemsSayWhere() {
        XCTAssertThrowsError(try ThemeFile.parse("name: X\ninterface:\n  page: purple-ish")) { error in
            XCTAssertEqual((error as? ThemeFile.Problem)?.line, 3)
        }
        XCTAssertThrowsError(try ThemeFile.parse("interface:\n  page: \"#000000\"")) { error in
            XCTAssertTrue((error as? ThemeFile.Problem)?.message.contains("name") ?? false)
        }
        XCTAssertThrowsError(try ThemeFile.parse("name: X\njust some words"))
    }

    func testWritesWhatItReads() throws {
        let theme = ThemeDefinition(name: "Round Trip", colors: [
            "interface.page": RGBA("#1B2233")!,
            "interface.divider": RGBA(1, 1, 1, 0.07),
            "intervals.root": RGBA("#000000")!,
            "sequencer.clips.chord": RGBA("#3366CC")!,
        ])
        let text = ThemeFile.write(theme, keyOrder: ["interface.page", "interface.divider", "intervals.root"],
                                   comments: ["interface.page": "behind everything"])
        XCTAssertEqual(try ThemeFile.parse(text), theme)
        XCTAssertTrue(text.contains("  page: \"#1B2233\"   # behind everything"))
        XCTAssertTrue(text.contains("sequencer:\n  clips:\n    chord: \"#3366CC\""))
    }
}

final class BuiltInThemeTests: XCTestCase {
    func testEveryBuiltInThemeReads() throws {
        let themes = BuiltInThemes.all()
        XCTAssertEqual(themes.map(\.id), BuiltInThemes.order)
        let defaults = BuiltInThemes.defaultTheme
        XCTAssertEqual(defaults.name, "Default")
        XCTAssertGreaterThan(defaults.colors.count, 60)
        for (id, theme) in themes {
            // Only colours the default has (a misspelt key would quietly do nothing)
            let unknown = Set(theme.colors.keys).subtracting(defaults.colors.keys)
            XCTAssertTrue(unknown.isEmpty, "\(id): \(unknown.sorted())")
        }
        // Every interval has a colour in the default
        for interval in ["root", "m2", "M2", "m3", "M3", "P4", "TT", "P5", "m6", "M6", "m7", "M7"] {
            XCTAssertNotNil(defaults.colors["intervals." + interval], interval)
        }
    }

    func testTheDefaultLaysOutAnExport() throws {
        let text = try XCTUnwrap(BuiltInThemes.text("default"))
        let layout = ThemeFile.layout(of: text)
        XCTAssertEqual(layout.order.first, "interface.page")
        XCTAssertEqual(layout.comments["interface.page"], "behind the pages (and the tab)")
        let defaults = BuiltInThemes.defaultTheme
        XCTAssertEqual(Set(layout.order), Set(defaults.colors.keys))
        // Written out the same way, it reads back the same
        XCTAssertEqual(try ThemeFile.parse(ThemeFile.write(defaults, keyOrder: layout.order, comments: layout.comments)), defaults)
    }
}
