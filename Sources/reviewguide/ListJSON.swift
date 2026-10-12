import Foundation
import ReviewGuideCore

/// The `list --json` document from docs/cli.md. Encodes absent values as explicit `null`s.
struct ListJSON: Encodable {
    var diff: Diff
    var placements: Placements?

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    enum Keys: String, CodingKey {
        case range, base, head, excluded, files, path, oldPath, status, placedIn, hunks
        case number, header, oldStart, oldCount, newStart, newCount, lines, kind, old, new, text
    }

    // `encode(_:forKey:)` with an Optional writes null; synthesized conformance would omit the key.
    func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: Keys.self)
        try root.encode(diff.range, forKey: .range)
        try root.encode(diff.base, forKey: .base)
        try root.encode(diff.head, forKey: .head)
        try root.encode(diff.excluded, forKey: .excluded)
        var files = root.nestedUnkeyedContainer(forKey: .files)
        for file in diff.files {
            var f = files.nestedContainer(keyedBy: Keys.self)
            try f.encode(file.path, forKey: .path)
            try f.encode(file.oldPath, forKey: .oldPath)
            try f.encode(file.status, forKey: .status)
            try f.encode(file.isFileChange ? placements?.sectionID(fileChange: file) : nil, forKey: .placedIn)
            var hunks = f.nestedUnkeyedContainer(forKey: .hunks)
            for hunk in file.hunks {
                var h = hunks.nestedContainer(keyedBy: Keys.self)
                try h.encode(hunk.number, forKey: .number)
                try h.encode(hunk.header, forKey: .header)
                try h.encode(hunk.oldStart, forKey: .oldStart)
                try h.encode(hunk.oldCount, forKey: .oldCount)
                try h.encode(hunk.newStart, forKey: .newStart)
                try h.encode(hunk.newCount, forKey: .newCount)
                var lines = h.nestedUnkeyedContainer(forKey: .lines)
                for (index, line) in hunk.lines.enumerated() {
                    var l = lines.nestedContainer(keyedBy: Keys.self)
                    try l.encode(line.kind, forKey: .kind)
                    try l.encode(line.old, forKey: .old)
                    try l.encode(line.new, forKey: .new)
                    try l.encode(line.text, forKey: .text)
                    try l.encode(line.isChange ? placements?.sectionID(file: file, hunk: hunk, index: index) : nil, forKey: .placedIn)
                }
            }
        }
    }
}
