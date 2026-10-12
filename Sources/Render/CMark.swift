import Foundation
import cmark_gfm
import cmark_gfm_extensions

typealias CMarkNode = UnsafeMutablePointer<cmark_node>

/// One parsed GFM document. The tree is mutable until `html()`; the class frees it.
final class CMarkDocument {
    private static let registered: Void = cmark_gfm_core_extensions_ensure_registered()
    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]

    private let parser: UnsafeMutablePointer<cmark_parser>
    let root: CMarkNode
    private let options: Int32
    /// Footnote labels in order of first reference, with the reference nodes that use each.
    private(set) var footnoteReferences: [(label: String, node: CMarkNode)] = []

    /// Parses `markdown`. With `footnotes`, every `[^label]` outside code becomes a reference node in
    /// `footnoteReferences`, whether or not the label is defined.
    init(_ markdown: String, footnotes: Bool) {
        _ = Self.registered
        options = CMARK_OPT_UNSAFE | (footnotes ? CMARK_OPT_FOOTNOTES : 0)
        parser = cmark_parser_new(options)!
        for name in Self.extensionNames {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        // cmark drops references to undefined labels, so define every label that looks referenced.
        var text = markdown
        if footnotes {
            let labels = Set(Self.candidateLabels(in: markdown))
            if !labels.isEmpty {
                text += "\n\n" + labels.sorted().map { "[^\($0)]: -\n" }.joined(separator: "\n")
            }
        }
        cmark_parser_feed(parser, text, text.utf8.count)
        root = cmark_parser_finish(parser)!
        if footnotes { collectFootnotes() }
    }

    deinit {
        cmark_node_free(root)
        cmark_parser_free(parser)
    }

    static func candidateLabels(in markdown: String) -> [String] {
        markdown.matches(of: /\[\^([^\]\s]+)\]/).map { String($0.output.1) }
    }

    /// cmark numbers referenced definitions 1...n, appends them to the root in that order, and replaces
    /// each reference's literal with its number.
    private func collectFootnotes() {
        var labels: [String] = []
        for def in children(of: root) where cmark_node_get_type(def) == CMARK_NODE_FOOTNOTE_DEFINITION {
            labels.append(literal(def))
            cmark_node_unlink(def)
            cmark_node_free(def)
        }
        for node in nodes(where: { cmark_node_get_type($0) == CMARK_NODE_FOOTNOTE_REFERENCE }) {
            guard let n = Int(literal(node)), labels.indices.contains(n - 1) else { continue }
            footnoteReferences.append((labels[n - 1], node))
        }
    }

    func children(of node: CMarkNode) -> [CMarkNode] {
        var result: [CMarkNode] = []
        var child = cmark_node_first_child(node)
        while let c = child { result.append(c); child = cmark_node_next(c) }
        return result
    }

    /// Pre-order list of matching nodes, safe to mutate afterwards.
    func nodes(where match: (CMarkNode) -> Bool) -> [CMarkNode] {
        var result: [CMarkNode] = []
        let iter = cmark_iter_new(root)
        defer { cmark_iter_free(iter) }
        while cmark_iter_next(iter) != CMARK_EVENT_DONE {
            if cmark_iter_get_event_type(iter) == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iter), match(node) {
                result.append(node)
            }
        }
        return result
    }

    func codeBlocks() -> [CMarkNode] { nodes(where: { cmark_node_get_type($0) == CMARK_NODE_CODE_BLOCK }) }

    /// 1-based story lines that `node` spans, inclusive.
    func lines(of node: CMarkNode) -> ClosedRange<Int> {
        Int(cmark_node_get_start_line(node))...Int(cmark_node_get_end_line(node))
    }

    func isTopLevel(_ node: CMarkNode) -> Bool { cmark_node_parent(node) == root }

    func literal(_ node: CMarkNode) -> String {
        cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
    }

    func fenceInfo(_ node: CMarkNode) -> String {
        cmark_node_get_fence_info(node).map { String(cString: $0) } ?? ""
    }

    /// Replaces `node` with raw HTML: an HTML block for a block node, inline HTML otherwise.
    func replace(_ node: CMarkNode, withHTML html: String, block: Bool) {
        let raw = makeHTML(html, block: block)
        cmark_node_insert_before(node, raw)
        cmark_node_unlink(node)
        cmark_node_free(node)
    }

    func makeHTML(_ html: String, block: Bool) -> CMarkNode {
        let raw = cmark_node_new(block ? CMARK_NODE_HTML_BLOCK : CMARK_NODE_HTML_INLINE)!
        cmark_node_set_literal(raw, html)
        return raw
    }

    /// Turns `> [!KIND]` blockquotes into `open`, the quote's remaining children, then `close`.
    /// `wrap` maps the kind (upper-cased, without brackets) to the opening and closing HTML, or `nil` to leave the quote.
    func rewriteAlerts(_ wrap: (String) -> (open: String, close: String)?) {
        for quote in nodes(where: { cmark_node_get_type($0) == CMARK_NODE_BLOCK_QUOTE }) {
            guard let para = cmark_node_first_child(quote), cmark_node_get_type(para) == CMARK_NODE_PARAGRAPH else { continue }
            var marker: [CMarkNode] = []
            var text = ""
            var child = cmark_node_first_child(para)
            while let c = child, cmark_node_get_type(c) == CMARK_NODE_TEXT {
                marker.append(c); text += literal(c); child = cmark_node_next(c)
            }
            if let c = child {
                let type = cmark_node_get_type(c)
                guard type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK else { continue }
                marker.append(c)
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[!"), trimmed.hasSuffix("]"),
                  let tags = wrap(String(trimmed.dropFirst(2).dropLast()).uppercased()) else { continue }
            for node in marker { cmark_node_unlink(node); cmark_node_free(node) }
            if cmark_node_first_child(para) == nil { cmark_node_unlink(para); cmark_node_free(para) }
            cmark_node_insert_before(quote, makeHTML(tags.open, block: true))
            for c in children(of: quote) { cmark_node_unlink(c); cmark_node_insert_before(quote, c) }
            cmark_node_insert_before(quote, makeHTML(tags.close, block: true))
            cmark_node_unlink(quote)
            cmark_node_free(quote)
        }
    }

    func html() -> String {
        guard let out = cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(out) }
        return String(cString: out)
    }
}
