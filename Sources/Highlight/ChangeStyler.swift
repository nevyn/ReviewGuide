import ReviewGuideCore

/// Change styling: pairs the deleted and added lines of each replacement in a hunk and marks the tokens that differ.
enum ChangeStyler {
    /// Pairs scoring below this stay unpaired.
    static let threshold = 0.5
    /// How many added lines past the last paired one a deleted line is compared with; bounds the work on big rewrites.
    static let lookahead = 16

    /// Changed UTF-8 byte ranges, sorted and disjoint, keyed by index into `lines`. Unpaired lines have no entry.
    static func changedRanges(in lines: [DiffLine]) -> [Int: [Range<Int>]] {
        var result: [Int: [Range<Int>]] = [:]
        var index = 0
        while index < lines.count {
            guard lines[index].kind == .del else { index += 1; continue }
            let dels = index..<(lines[index...].firstIndex { $0.kind != .del } ?? lines.count)
            let adds = dels.upperBound..<(lines[dels.upperBound...].firstIndex { $0.kind != .add } ?? lines.count)
            index = adds.upperBound
            for (del, add) in pairs(dels: dels, adds: adds, lines: lines) {
                result[del] = add.old
                result[add.index] = add.new
            }
        }
        return result
    }

    private struct Pair {
        var index: Int
        var old: [Range<Int>]
        var new: [Range<Int>]
    }

    /// Greedy in-order pairing: each deleted line takes its best-scoring added line after the previous pair's,
    /// so pairs never cross.
    private static func pairs(dels: Range<Int>, adds: Range<Int>, lines: [DiffLine]) -> [(Int, Pair)] {
        guard !adds.isEmpty else { return [] }
        let addTokens = adds.map { tokenize(lines[$0].text) }
        var result: [(Int, Pair)] = []
        var nextAdd = adds.lowerBound
        for del in dels where nextAdd < adds.upperBound {
            let old = tokenize(lines[del].text)
            var best: (score: Double, index: Int, pair: Pair)?
            for add in nextAdd..<min(adds.upperBound, nextAdd + lookahead) {
                let new = addTokens[add - adds.lowerBound]
                let comparison = compare(old, new)
                if comparison.score >= threshold, comparison.score > (best?.score ?? -1) {
                    best = (comparison.score, add, Pair(index: add, old: comparison.old, new: comparison.new))
                }
            }
            guard let best else { continue }
            result.append((del, best.pair))
            nextAdd = best.index + 1
        }
        return result
    }

    struct Token: Equatable {
        var text: Substring
        var bytes: Range<Int>
        var isWhitespace: Bool
    }

    /// Words (letters, digits, `_`, combining marks), whitespace runs, and every other scalar on its own.
    static func tokenize(_ line: String) -> [Token] {
        enum Kind { case word, space, other }
        func kind(_ scalar: Unicode.Scalar) -> Kind {
            if scalar == "_" || scalar.properties.isAlphabetic || scalar.properties.numericType != nil { return .word }
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: return .word
            default: break
            }
            return scalar.properties.isWhitespace ? .space : .other
        }
        var tokens: [Token] = []
        var start = line.unicodeScalars.startIndex
        var startByte = 0
        var byte = 0
        var current: Kind?
        for index in line.unicodeScalars.indices {
            let scalar = line.unicodeScalars[index]
            let next = kind(scalar)
            if let current, current != next || current == .other {
                tokens.append(Token(text: line[start..<index], bytes: startByte..<byte, isWhitespace: current == .space))
                start = index
                startByte = byte
            }
            current = next
            byte += scalar.utf8.count
        }
        if let current {
            tokens.append(Token(text: line[start...], bytes: startByte..<byte, isWhitespace: current == .space))
        }
        return tokens
    }

    /// Similarity over non-whitespace tokens (2 * matches / total) and the changed byte ranges on each side.
    /// A pair in which every non-whitespace token changed scores 0, so it never pairs.
    static func compare(_ old: [Token], _ new: [Token]) -> (score: Double, old: [Range<Int>], new: [Range<Int>]) {
        let difference = new.map(\.text).difference(from: old.map(\.text))
        var oldChanged = Set<Int>()
        var newChanged = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): oldChanged.insert(offset)
            case .insert(let offset, _, _): newChanged.insert(offset)
            }
        }
        let oldWords = old.indices.filter { !old[$0].isWhitespace }
        let newWords = new.indices.filter { !new[$0].isWhitespace }
        let matches = oldWords.filter { !oldChanged.contains($0) }.count
        let total = oldWords.count + newWords.count
        let score = total == 0 ? 1 : 2 * Double(matches) / Double(total)
        return (score, ranges(old, oldChanged), ranges(new, newChanged))
    }

    private static func ranges(_ tokens: [Token], _ changed: Set<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for index in tokens.indices where changed.contains(index) {
            let bytes = tokens[index].bytes
            if let last = result.last, last.upperBound == bytes.lowerBound {
                result[result.count - 1] = last.lowerBound..<bytes.upperBound
            } else {
                result.append(bytes)
            }
        }
        return result
    }

    /// Splits syntax runs at the changed ranges' edges and flags the runs inside them; then joins equal neighbours.
    static func merge(_ runs: StyledLine, changed: [Range<Int>]) -> StyledLine {
        guard !changed.isEmpty else { return runs }
        var cuts = Set<Int>()
        for range in changed { cuts.insert(range.lowerBound); cuts.insert(range.upperBound) }
        var pieces: StyledLine = []
        for run in runs {
            var lower = run.bytes.lowerBound
            for cut in cuts.filter({ run.bytes.lowerBound < $0 && $0 < run.bytes.upperBound }).sorted() + [run.bytes.upperBound] {
                let isChanged = changed.contains { $0.contains(lower) }
                pieces.append(StyledRun(bytes: lower..<cut, capture: run.capture, changed: run.changed || isChanged))
                lower = cut
            }
        }
        var result: StyledLine = []
        for piece in pieces {
            if let last = result.last, last.capture == piece.capture, last.changed == piece.changed,
               last.bytes.upperBound == piece.bytes.lowerBound {
                result[result.count - 1].bytes = last.bytes.lowerBound..<piece.bytes.upperBound
            } else {
                result.append(piece)
            }
        }
        return result
    }
}
