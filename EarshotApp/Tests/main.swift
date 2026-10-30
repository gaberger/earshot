// Tests for the rich summary editor, run in a real NSTextView with the app's own editor code.
// Run: bash EarshotApp/Tests/run.sh
import AppKit
import SwiftUI
_ = NSApplication.shared
let md = """
# Acme renewal

*Meeting minutes · Oct 30, 2026 · 1 min*

## Overview
Review of the **Acme** renewal.

## Key points
- Acme wants a decision by November 15th.
- Their budget is $80,000.

## Action items
- [ ] **Gary** — Send a revised quote. *(due Monday)*
"""
var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
    let ok = got == want
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; print("--- want ---\n\(want)--- got ---\n\(got)---") }
}
func checkTrue(_ name: String, _ ok: Bool) { print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1 } }

@MainActor func runTests() {
    let controller = RichEditorController()
    let editor = RichSummaryEditor(markdown: .constant(md), controller: controller)
    let coordinator = editor.makeCoordinator()
    func fresh() -> NSTextView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = scroll
        tv.isRichText = true; tv.allowsUndo = true; tv.delegate = coordinator
        tv.textStorage?.setAttributedString(RichMarkdown.attributed(from: md))
        tv.typingAttributes = RichMarkdown.attributes(.body)
        win.makeFirstResponder(tv)
        controller.textView = tv
        return tv
    }
    func save(_ tv: NSTextView) -> String { RichMarkdown.markdown(from: tv.attributedString()) }
    func cursor(after text: String, in tv: NSTextView) {
        let r = (tv.string as NSString).range(of: text); precondition(r.location != NSNotFound, text)
        tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
    }
    func returnKey(_ tv: NSTextView) { tv.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
    func type(_ s: String, _ tv: NSTextView) { tv.insertText(s, replacementRange: tv.selectedRange()) }

    var tv = fresh()
    checkTrue("no marker characters in the text (macOS draws them)", !tv.string.contains("\t"))
    check("open and save without typing changes nothing", save(tv), md + "\n")

    cursor(after: "November 15th.", in: tv); returnKey(tv); type("A new point", tv)
    check("Return in a bullet list adds a bullet", save(tv), md.replacingOccurrences(of: "November 15th.\n", with: "November 15th.\n- A new point\n") + "\n")

    tv = fresh(); cursor(after: "(due Monday)", in: tv); returnKey(tv); type("Call Matt", tv)
    check("new action item after italic text is plain", save(tv), md + "\n- [ ] Call Matt\n")

    tv = fresh(); cursor(after: "Overview", in: tv); returnKey(tv); type("A plain line", tv)
    check("Return after a heading gives body text", save(tv),
          md.replacingOccurrences(of: "## Overview\n", with: "## Overview\nA plain line\n") + "\n")

    tv = fresh(); cursor(after: "$80,000.", in: tv); returnKey(tv); returnKey(tv); type("After the list", tv)
    check("Return on an empty bullet ends the list", save(tv),
          md.replacingOccurrences(of: "$80,000.\n", with: "$80,000.\nAfter the list\n") + "\n")

    tv = fresh(); cursor(after: "renewal.", in: tv)
    tv.setSelectedRange(NSRange(location: tv.selectedRange().location - 8, length: 0))
    type("contract ", tv)
    check("typing inside a paragraph", save(tv), md.replacingOccurrences(of: "Acme** renewal.", with: "Acme** contract renewal.") + "\n")

    tv = fresh(); cursor(after: "renewal.", in: tv); controller.toggleList(.bullet)
    check("bullet button on a text line", save(tv), md.replacingOccurrences(of: "\nReview of", with: "\n- Review of") + "\n")
    checkTrue("…and no marker characters added", !tv.string.contains("\t"))
    controller.toggleList(.bullet)
    check("bullet button again turns it back", save(tv), md + "\n")

    tv = fresh(); let r = (tv.string as NSString).range(of: "budget")
    tv.setSelectedRange(r); controller.toggleTrait(.boldFontMask)
    check("bold button", save(tv), md.replacingOccurrences(of: "Their budget", with: "Their **budget**") + "\n")

    tv = fresh(); cursor(after: "$80,000.", in: tv); controller.toggleList(.task)
    check("checkbox button on a bullet", save(tv), md.replacingOccurrences(of: "- Their budget", with: "- [ ] Their budget") + "\n")
}
MainActor.assumeIsolated { runTests() }
print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
