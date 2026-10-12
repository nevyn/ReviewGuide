import Foundation
import StoryGrafterCore
@testable import Highlight

/// The text and capture of every styled run, line by line, for readable expectations.
func styledTokens(_ source: String, _ lines: [StyledLine]) -> [(text: String, capture: String?, changed: Bool)] {
    let sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)
    var result: [(String, String?, Bool)] = []
    for (text, runs) in zip(sourceLines, lines) {
        let bytes = Array(text.utf8)
        for run in runs {
            result.append((String(decoding: bytes[run.bytes], as: UTF8.self), run.capture, run.changed))
        }
    }
    return result
}

/// The capture of the run that covers `token`'s first occurrence in the snippet.
func capture(of token: String, in source: String, language: String) -> String? {
    let lines = Highlighter(diff: emptyDiff, readBlob: { _, _ in nil }).styles(source: source, language: language)
    return capture(of: token, in: source, lines: lines)
}

func capture(of token: String, in source: String, lines: [StyledLine]) -> String? {
    let sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)
    for (text, runs) in zip(sourceLines, lines) {
        guard let range = text.range(of: token) else { continue }
        let start = text.utf8.distance(from: text.startIndex, to: range.lowerBound)
        return runs.first { $0.bytes.contains(start) }?.capture
    }
    return nil
}

let emptyDiff = Diff(range: "a...b", base: "base", head: "head", files: [], excluded: [])
