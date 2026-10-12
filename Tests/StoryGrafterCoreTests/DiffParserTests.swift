import Testing
@testable import StoryGrafterCore

@Suite struct DiffParserTests {
    @Test func added() throws {
        let files = DiffParser.parse(try Fixture.diff("added"))
        #expect(files.count == 1)
        let f = try #require(files.first)
        #expect(f.path == "Hello.swift" && f.oldPath == nil && f.status == .added)
        #expect(f.hunks.count == 1)
        let h = f.hunks[0]
        #expect(h.number == 1 && h.oldStart == 0 && h.oldCount == 0 && h.newStart == 1 && h.newCount == 3)
        #expect(h.lines.map(\.kind) == [.add, .add, .add])
        #expect(h.lines.map(\.new) == [1, 2, 3])
        #expect(h.lines.allSatisfy { $0.old == nil })
        #expect(h.lines[1].text == "    print(\"hi\")")
    }

    @Test func deleted() throws {
        let f = try #require(DiffParser.parse(try Fixture.diff("deleted")).first)
        #expect(f.path == "Hello.swift" && f.status == .deleted)
        #expect(f.hunks[0].lines.map(\.old) == [1, 2, 3])
        #expect(f.hunks[0].lines.allSatisfy { $0.kind == .del && $0.new == nil })
    }

    @Test func pureRename() throws {
        let f = try #require(DiffParser.parse(try Fixture.diff("renamed-pure")).first)
        #expect(f.path == "Moved.txt" && f.oldPath == "Mover.txt" && f.status == .renamed)
        #expect(f.isFileChange)
    }

    @Test func renameWithChange() throws {
        let f = try #require(DiffParser.parse(try Fixture.diff("renamed-changed")).first)
        #expect(f.path == "Renamed.txt" && f.oldPath == "Moved.txt" && f.status == .renamed)
        let h = try #require(f.hunks.first)
        #expect(h.header == "row 11" && h.oldStart == 12 && h.newStart == 12)
        let del = try #require(h.lines.first { $0.kind == .del })
        let add = try #require(h.lines.first { $0.kind == .add })
        #expect(del.old == 15 && del.text == "row 15")
        #expect(add.new == 15 && add.text == "row fifteen")
    }

    @Test func copied() throws {
        let f = try #require(DiffParser.parse(try Fixture.diff("copied")).first)
        #expect(f.path == "Copy.txt" && f.oldPath == "Renamed.txt" && f.status == .copied)
        #expect(f.hunks.count == 1)
    }

    @Test(arguments: ["binary-added", "binary-modified"])
    func binary(fixture: String) throws {
        let f = try #require(DiffParser.parse(try Fixture.diff(fixture)).first)
        #expect(f.path == "blob.bin" && f.status == .binary && f.isFileChange)
    }

    @Test func modeOnly() throws {
        let f = try #require(DiffParser.parse(try Fixture.diff("mode-only")).first)
        #expect(f.path == "keep.txt" && f.status == .mode && f.isFileChange)
    }

    @Test func modeWithContentIsModified() throws {
        let f = try #require(DiffParser.parse(try Fixture.diff("mode-and-content")).first)
        #expect(f.status == .modified)
        let h = try #require(f.hunks.first)
        #expect(h.oldStart == 1 && h.oldCount == 1 && h.newStart == 1 && h.newCount == 1)
        #expect(h.lines == [DiffLine(kind: .del, old: 1, new: nil, text: "keep"), DiffLine(kind: .add, old: nil, new: 1, text: "kept")])
    }

    @Test func quotedPathsAndTabs() throws {
        let files = DiffParser.parse(try Fixture.diff("quoted-paths"))
        #expect(files.map(\.path) == ["My File.swift", "quo\"te ü.txt"])
        #expect(files.allSatisfy { $0.status == .modified && $0.hunks.count == 1 })
        #expect(files[1].hunks[0].header == "")
    }

    @Test func noNewlineMarkersAreDropped() throws {
        let h = try #require(DiffParser.parse(try Fixture.diff("no-newline")).first?.hunks.first)
        #expect(h.lines == [
            DiffLine(kind: .context, old: 1, new: 1, text: "a"),
            DiffLine(kind: .del, old: 2, new: nil, text: "b"),
            DiffLine(kind: .add, old: nil, new: 2, text: "c"),
        ])
    }

    @Test func twoHunksWithAndWithoutFunctionHeader() throws {
        let f = try #require(DiffParser.parse(try Fixture.diff("two-hunks")).first)
        #expect(f.hunks.map(\.number) == [1, 2])
        #expect(f.hunks.map(\.header) == ["", "line 14"])
        #expect(f.hunks[1].oldStart == 15 && f.hunks[1].oldCount == 6)
        #expect(f.hunks[1].lines[3] == DiffLine(kind: .del, old: 18, new: nil, text: "line 18"))
    }

    /// A deleted line `-- sql comment` prints as `--- sql comment`; it must not start a file header.
    @Test(arguments: ["blank-context-and-dashes", "suppress-blank-empty"])
    func blankContextAndDashes(fixture: String) throws {
        let files = DiffParser.parse(try Fixture.diff(fixture))
        #expect(files.count == 1)
        let h = try #require(files.first?.hunks.first)
        #expect(h.lines.count == 9)
        #expect(h.lines[1] == DiffLine(kind: .context, old: 2, new: 2, text: ""))
        #expect(h.lines[7] == DiffLine(kind: .del, old: 7, new: nil, text: "-- sql comment"))
        #expect(h.lines[8] == DiffLine(kind: .context, old: 8, new: 7, text: "}"))
    }

    @Test func severalFilesKeepOrderAndNumberHunksPerFile() throws {
        let text = try Fixture.diff("two-hunks") + Fixture.diff("binary-modified") + Fixture.diff("added")
        let files = DiffParser.parse(text)
        #expect(files.map(\.path) == ["base.txt", "blob.bin", "Hello.swift"])
        #expect(files[2].hunks.map(\.number) == [1])
    }

    @Test func crlfIsStripped() {
        let text = "diff --git a/w.txt b/w.txt\r\n--- a/w.txt\r\n+++ b/w.txt\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n"
        let h = DiffParser.parse(text).first?.hunks.first
        #expect(h?.lines.map(\.text) == ["a", "b"])
    }

    @Test func binaryWithSpaceTakesPathFromGitLine() {
        let text = "diff --git a/my b/pic.png b/my b/pic.png\nnew file mode 100644\nindex 0000000..1111111\nBinary files /dev/null and b/my b/pic.png differ\n"
        let f = DiffParser.parse(text).first
        #expect(f?.path == "my b/pic.png" && f?.status == .binary)
    }

    @Test(.timeLimit(.minutes(1))) func largeHunkParsesInLinearTime() {
        let count = 300_000
        var text = "diff --git a/big.c b/big.c\nnew file mode 100644\n--- /dev/null\n+++ b/big.c\n@@ -0,0 +1,\(count) @@\n"
        text += String(repeating: "+int x;\n", count: count)
        let start = ContinuousClock.now
        let files = DiffParser.parse(text)
        #expect(files.first?.hunks.first?.lines.count == count)
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}
