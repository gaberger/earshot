// Rich-text editing for summaries. The summary is stored as a small Markdown dialect
// (# title, ## heading, - bullet, - [ ] task, - [x] done, **bold**, *italic*); this file
// turns it into formatted text for NSTextView and back again.

import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// Which kind of paragraph this is: title, heading or body. Lists live in the paragraph style.
    static let earshotBlock = NSAttributedString.Key("EarshotBlock")
}

enum RichMarkdown {
    enum Block: String { case title, heading, body }

    enum ListKind {
        case bullet, task, done

        var format: NSTextList.MarkerFormat {
            switch self {
            case .bullet: .disc
            case .task: .box
            case .done: .check
            }
        }

        init?(_ format: NSTextList.MarkerFormat) {
            switch format {
            case .box: self = .task
            case .check: self = .done
            case .disc, .circle, .hyphen, .square, .diamond: self = .bullet
            default: return nil
            }
        }
    }

    static let bodyFont = NSFont.systemFont(ofSize: 14)

    static func font(for block: Block) -> NSFont {
        switch block {
        case .title: NSFont.systemFont(ofSize: 22, weight: .bold)
        case .heading: NSFont.systemFont(ofSize: 16, weight: .semibold)
        case .body: bodyFont
        }
    }

    static func paragraphStyle(_ block: Block, list: ListKind?) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        p.paragraphSpacing = block == .title ? 8 : 4
        p.paragraphSpacingBefore = block == .heading ? 12 : 0
        if let list {
            p.textLists = [NSTextList(markerFormat: list.format, options: 0)]
            p.tabStops = [NSTextTab(textAlignment: .left, location: 6),
                          NSTextTab(textAlignment: .left, location: 24)]
            p.headIndent = 24
        }
        return p
    }

    static func attributes(_ block: Block, list: ListKind? = nil) -> [NSAttributedString.Key: Any] {
        [.font: font(for: block),
         .foregroundColor: NSColor.textColor,
         .paragraphStyle: paragraphStyle(block, list: list),
         .earshotBlock: block.rawValue]
    }

    /// NSTextView keeps a list item's marker as text at the start of the paragraph: "\t•\t".
    static func markerPrefix(_ list: ListKind) -> String {
        "\t" + NSTextList(markerFormat: list.format, options: 0).marker(forItemNumber: 1) + "\t"
    }

    // MARK: Markdown → rich text

    static func attributed(from markdown: String) -> NSAttributedString {
        var paragraphs: [(NSAttributedString, Block, ListKind?)] = []
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("<!--") { continue }
            var block = Block.body
            var list: ListKind?
            var text = line
            if line.hasPrefix("# ") {
                block = .title
                text = String(line.dropFirst(2))
            } else if line.hasPrefix("#") {
                block = .heading
                text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            } else if let m = ["- [ ] ", "* [ ] "].first(where: line.hasPrefix) {
                list = .task
                text = String(line.dropFirst(m.count))
            } else if let m = ["- [x] ", "- [X] ", "* [x] "].first(where: line.hasPrefix) {
                list = .done
                text = String(line.dropFirst(m.count))
            } else if let m = ["- ", "* ", "• "].first(where: line.hasPrefix) {
                list = .bullet
                text = String(line.dropFirst(m.count))
            }
            let para = NSMutableAttributedString()
            if let list { para.append(NSAttributedString(string: markerPrefix(list), attributes: attributes(block, list: list))) }
            para.append(inline(text, block: block, list: list))
            paragraphs.append((para, block, list))
        }
        let out = NSMutableAttributedString()
        for (i, (para, block, list)) in paragraphs.enumerated() {
            out.append(para)
            // A paragraph's newline carries its style, so it gets the same attributes.
            if i < paragraphs.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: attributes(block, list: list)))
            }
        }
        return out
    }

    /// Body text keeps **bold** and *italic*; titles and headings are plain text in their own font.
    static func inline(_ text: String, block: Block, list: ListKind?) -> NSAttributedString {
        let attrs = attributes(block, list: list)
        guard block == .body else {
            return NSAttributedString(string: text.replacingOccurrences(of: "**", with: ""), attributes: attrs)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: attrs)
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var font = bodyFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            }
            var a = attrs
            a[.font] = font
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: a))
        }
        return out
    }

    // MARK: Rich text → Markdown

    static func markdown(from text: NSAttributedString) -> String {
        let ns = text.string as NSString
        var lines: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            guard range.length > 0 else { return }
            let attrs = text.attributes(at: range.location, effectiveRange: nil)
            let block = Block(rawValue: attrs[.earshotBlock] as? String ?? "") ?? guessBlock(attrs[.font] as? NSFont)
            let list = ((attrs[.paragraphStyle] as? NSParagraphStyle)?.textLists.first).flatMap { ListKind($0.markerFormat) }
            let content = stripMarker(text.attributedSubstring(from: range))
            let plain = content.string.trimmingCharacters(in: .whitespaces)
            guard !plain.isEmpty else { return }
            switch (block, list) {
            case (.title, _):
                if !lines.isEmpty { lines.append("") }
                lines += ["# " + plain, ""]
            case (.heading, _):
                if !lines.isEmpty && lines.last != "" { lines.append("") }
                lines.append("## " + plain)
            case (.body, .bullet?): lines.append("- " + inlineMarkdown(content))
            case (.body, .task?): lines.append("- [ ] " + inlineMarkdown(content))
            case (.body, .done?): lines.append("- [x] " + inlineMarkdown(content))
            case (.body, nil): lines.append(inlineMarkdown(content))
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    static func stripMarker(_ s: NSAttributedString) -> NSAttributedString {
        guard let m = s.string.range(of: #"^\t[^\t]*\t"#, options: .regularExpression) else { return s }
        let cut = NSRange(m, in: s.string).length
        return s.attributedSubstring(from: NSRange(location: cut, length: s.length - cut))
    }

    static func guessBlock(_ font: NSFont?) -> Block {
        guard let font else { return .body }
        if font.pointSize >= 20 { return .title }
        if font.pointSize >= 15.5 && NSFontManager.shared.traits(of: font).contains(.boldFontMask) { return .heading }
        return .body
    }

    static func inlineMarkdown(_ s: NSAttributedString) -> String {
        var out = ""
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, range, _ in
            let piece = (s.string as NSString).substring(with: range)
            let traits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let bold = traits.contains(.boldFontMask), italic = traits.contains(.italicFontMask)
            let core = piece.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty, bold || italic else {
                out += piece
                return
            }
            // Spaces stay outside the markers, or Markdown won't recognise them.
            let lead = String(piece.prefix { $0 == " " })
            let trail = String(piece.reversed().prefix { $0 == " " })
            let mark = bold && italic ? "***" : bold ? "**" : "*"
            out += lead + mark + core + mark + trail
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Editing a paragraph

    static func listKind(of para: NSAttributedString) -> ListKind? {
        guard para.length > 0 else { return nil }
        let style = para.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        return style?.textLists.first.flatMap { ListKind($0.markerFormat) }
    }

    static func block(of para: NSAttributedString) -> Block {
        guard para.length > 0 else { return .body }
        return Block(rawValue: para.attribute(.earshotBlock, at: 0, effectiveRange: nil) as? String ?? "") ?? .body
    }

    /// Gives one paragraph (with or without its newline) a new block style and list kind.
    static func restyle(_ para: NSMutableAttributedString, block: Block, list: ListKind?) {
        let oldBlock = self.block(of: para)
        let hadNewline = para.string.hasSuffix("\n")
        if hadNewline { para.deleteCharacters(in: NSRange(location: para.length - 1, length: 1)) }
        if let m = para.string.range(of: #"^\t[^\t]*\t"#, options: .regularExpression) {
            para.deleteCharacters(in: NSRange(m, in: para.string))
        }
        let attrs = attributes(block, list: list)
        let whole = NSRange(location: 0, length: para.length)
        if block != .body || oldBlock != .body {
            para.setAttributes(attrs, range: whole)  // headings have one font; leaving one resets it
        } else {
            para.addAttributes([.paragraphStyle: attrs[.paragraphStyle]!, .earshotBlock: block.rawValue], range: whole)
        }
        if let list { para.insert(NSAttributedString(string: markerPrefix(list), attributes: attrs), at: 0) }
        if hadNewline { para.append(NSAttributedString(string: "\n", attributes: attrs)) }
    }
}

// MARK: - Editor

/// Lets the formatting buttons reach the text view.
@MainActor
final class RichEditorController: ObservableObject {
    weak var textView: NSTextView?

    func setBlock(_ block: RichMarkdown.Block) {
        transformParagraphs { RichMarkdown.restyle($0, block: block, list: nil) }
    }

    /// Turns the selected paragraphs into list items of this kind, or back into text if they already are.
    func toggleList(_ kind: RichMarkdown.ListKind) {
        transformParagraphs { para in
            let off = RichMarkdown.listKind(of: para) == kind
            RichMarkdown.restyle(para, block: .body, list: off ? nil : kind)
        }
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let fm = NSFontManager.shared
        let sel = tv.selectedRange()
        guard sel.length > 0 else {
            // Nothing selected: change what is typed next.
            var typing = tv.typingAttributes
            let f = typing[.font] as? NSFont ?? RichMarkdown.bodyFont
            typing[.font] = fm.traits(of: f).contains(trait) ? fm.convert(f, toNotHaveTrait: trait)
                                                             : fm.convert(f, toHaveTrait: trait)
            tv.typingAttributes = typing
            return
        }
        var allHave = true
        storage.enumerateAttribute(.font, in: sel) { v, _, _ in
            if let f = v as? NSFont, !fm.traits(of: f).contains(trait) { allHave = false }
        }
        guard tv.shouldChangeText(in: sel, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: sel) { v, r, _ in
            let f = v as? NSFont ?? RichMarkdown.bodyFont
            storage.addAttribute(.font, value: allHave ? fm.convert(f, toNotHaveTrait: trait)
                                                       : fm.convert(f, toHaveTrait: trait), range: r)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    /// Rebuilds the selected paragraphs and swaps them in as one undoable change.
    private func transformParagraphs(_ change: (NSMutableAttributedString) -> Void) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let whole = ns.paragraphRange(for: tv.selectedRange())
        let result = NSMutableAttributedString()
        if whole.length == 0 {
            let empty = NSMutableAttributedString(string: "", attributes: tv.typingAttributes)
            change(empty)
            result.append(empty)
        } else {
            var at = whole.location
            while at < NSMaxRange(whole) {
                let pr = ns.paragraphRange(for: NSRange(location: at, length: 0))
                let para = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: pr))
                change(para)
                result.append(para)
                at = NSMaxRange(pr)
            }
        }
        guard tv.shouldChangeText(in: whole, replacementString: result.string) else { return }
        storage.replaceCharacters(in: whole, with: result)
        tv.didChangeText()
        let end = result.string.hasSuffix("\n") ? result.length - 1 : result.length
        tv.setSelectedRange(NSRange(location: whole.location + end, length: 0))
        if result.length > 0 {
            tv.typingAttributes = result.attributes(at: max(0, end - 1), effectiveRange: nil)
        }
    }
}

/// The summary as editable formatted text. Reads and writes Markdown through `markdown`.
struct RichSummaryEditor: NSViewRepresentable {
    @Binding var markdown: String
    let controller: RichEditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = true
        tv.allowsUndo = true
        tv.usesFontPanel = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.delegate = context.coordinator
        scroll.drawsBackground = false
        tv.textStorage?.setAttributedString(RichMarkdown.attributed(from: markdown))
        tv.typingAttributes = RichMarkdown.attributes(.body)
        context.coordinator.lastMarkdown = markdown
        controller.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        // Reload only for changes that came from outside the editor.
        guard markdown != context.coordinator.lastMarkdown, let tv = scroll.documentView as? NSTextView else { return }
        tv.textStorage?.setAttributedString(RichMarkdown.attributed(from: markdown))
        context.coordinator.lastMarkdown = markdown
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichSummaryEditor
        var lastMarkdown = ""

        init(_ parent: RichSummaryEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let md = RichMarkdown.markdown(from: tv.attributedString())
            lastMarkdown = md
            parent.markdown = md
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Return at the end of a title or heading starts ordinary text, as in Notes and Pages.
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let ns = tv.string as NSString
            let loc = min(tv.selectedRange().location, max(0, ns.length - 1))
            guard ns.length > 0,
                  RichMarkdown.block(of: tv.attributedString().attributedSubstring(
                      from: ns.paragraphRange(for: NSRange(location: loc, length: 0)))) != .body
            else { return false }
            tv.insertText("\n", replacementRange: tv.selectedRange())
            tv.typingAttributes = RichMarkdown.attributes(.body)
            return true
        }
    }
}
