import XCTest
@testable import SpotCore

final class LibraryImportTests: XCTestCase {
    private func bundle() -> LibraryBundle {
        LibraryBundle(
            bundle: .init(id: "test", name: "Test"),
            scales: [
                ScaleDefinition(id: "user.a", name: "Scale A", formula: Formula("1 2 3 5 6")!),
                ScaleDefinition(id: "builtin.scale.major", name: "My Major", formula: Formula("1 2 3 4 5 6 7")!),
            ],
            chords: [ChordDefinition(id: "user.c", name: "Chord C", symbols: ["zz"], formula: Formula("1 3 5")!)],
            shapes: [Shape(id: "user.s", definitionId: "user.a", kind: .scale, system: "Mine", name: "Shape",
                           tuningId: Tuning.standard.id,
                           notes: [ShapeNote(string: 0, fret: 0, degree: Degree(1), finger: 1)])]
        )
    }

    func testFindsConflicts() {
        let plan = LibraryImport(bundle(), existingIds: ["user.a", "builtin.scale.major"], builtInIds: ["builtin.scale.major"])
        XCTAssertEqual(plan.items.count, 4)
        XCTAssertEqual(Set(plan.conflicts.map(\.id)), ["user.a", "builtin.scale.major"])
        XCTAssertEqual(plan.conflicts.first { $0.id == "builtin.scale.major" }?.isBuiltIn, true)
        XCTAssertEqual(plan.issues, [])
    }

    func testSkipAndReplace() {
        let plan = LibraryImport(bundle(), existingIds: ["user.a", "user.c"], builtInIds: [])
        let result = plan.resolved(["user.a": .skip, "user.c": .replace])
        XCTAssertEqual(result.scales.map(\.id), ["builtin.scale.major"])
        XCTAssertEqual(result.chords.map(\.id), ["user.c"])
        // The shape still points at the existing user.a
        XCTAssertEqual(result.shapes.first?.definitionId, "user.a")
    }

    func testKeepBothRenamesAndFollowsShapes() {
        let plan = LibraryImport(bundle(), existingIds: ["user.a"], builtInIds: [])
        let result = plan.resolved(default: .keepBoth, makeId: { "new" })
        XCTAssertEqual(result.scales[0].id, "user.new")
        XCTAssertEqual(result.scales[0].name, "Scale A (2)")
        XCTAssertEqual(result.shapes[0].definitionId, "user.new")
    }

    func testBuiltInsAreNeverReplaced() {
        let plan = LibraryImport(bundle(), existingIds: ["builtin.scale.major"], builtInIds: ["builtin.scale.major"])
        let result = plan.resolved(["builtin.scale.major": .replace], makeId: { "copy" })
        XCTAssertEqual(result.scales[1].id, "user.copy")
        XCTAssertEqual(result.scales[1].name, "My Major (2)")
    }

    func testShapesRoundTripAndValidate() throws {
        let original = bundle()
        XCTAssertEqual(try LibraryBundle.decode(from: original.encoded()), original)

        var broken = original
        broken.shapes[0].notes.append(ShapeNote(string: 1, fret: 1, degree: Degree("b3")!))
        XCTAssertTrue(broken.validate().contains { $0.contains("outside user.a") })
    }

    func testFilesWithoutShapesStillDecode() throws {
        let json = #"{"format": "spot.library", "version": 1, "bundle": {"id": "x", "name": "X"}, "chords": []}"#
        let decoded = try LibraryBundle.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.shapes, [])
        XCTAssertEqual(decoded.scales, [])
        XCTAssertFalse(String(decoding: try decoded.encoded(), as: UTF8.self).contains("shapes"))
    }
}
