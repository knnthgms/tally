import AppKit
import SwiftUI
import TallyEngine

/// Plain-text editor that draws each line's result right-aligned in a column, Numi-style.
final class CalcTextView: NSTextView {
    var results: [LineResult] = [] {
        didSet { applyHighlighting(); refreshOverlay() }
    }
    var style = EditorStyle(theme: .system, fontID: "system", fontSize: 15, lineSpacing: 5, resultFraction: 0.4,
                            highlightLine: true) {
        didSet { if style != oldValue { applyStyle() } }
    }
    /// Text to put on the clipboard when a result is clicked (lets settings choose number-only copies).
    var copyText: ((Int) -> String?)?

    private var copiedLine: Int?
    private var hoverLine: Int?
    private var baseFont: NSFont { FontCatalog.font(style.fontID, size: style.fontSize) }
    private var paragraph = NSParagraphStyle()

    var resultColumnWidth: CGFloat { max(120, bounds.width * style.resultFraction) }

    func applyStyle() {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.lineSpacing
        paragraph = p
        let t = style.theme
        backgroundColor = t.background
        insertionPointColor = t.text
        selectedTextAttributes = [.backgroundColor: t.selection]
        defaultParagraphStyle = p
        updateContainerWidth()
        applyHighlighting()
        refreshOverlay()
    }

    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        // Always match the visible width so the results column stays on screen.
        if let clip = enclosingScrollView?.contentView { size.width = clip.bounds.width }
        super.setFrameSize(size)
        overlay.frame = bounds
        updateContainerWidth()
    }

    private func updateContainerWidth() {
        guard let tc = textContainer else { return }
        let w = max(80, bounds.width - resultColumnWidth - textContainerInset.width * 2)
        if abs(tc.size.width - w) > 0.5 { tc.size = NSSize(width: w, height: .greatestFiniteMagnitude) }
    }

    override func didChangeText() {
        super.didChangeText()
        refreshOverlay()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if style.highlightLine { overlay.needsDisplay = true }
    }

    private func refreshOverlay() {
        overlay.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Result layout

    private struct Slot { let line: Int; let rect: NSRect; let text: String }

    private func lineRects() -> [(line: Int, range: NSRange, rect: NSRect)] {
        guard let lm = layoutManager else { return [] }
        let ns = string as NSString
        var out: [(Int, NSRange, NSRect)] = []
        var offset = 0
        for (i, line) in string.components(separatedBy: "\n").enumerated() {
            let len = (line as NSString).length
            defer { offset += len + 1 }
            guard len > 0, offset < ns.length else { continue }
            let range = NSRange(location: offset, length: len)
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var frag = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            frag.origin.y += textContainerOrigin.y
            out.append((i, range, frag))
        }
        return out
    }

    private func slots() -> [Slot] {
        let right = bounds.width - textContainerInset.width
        let left = right - resultColumnWidth + 16
        return lineRects().compactMap { line, _, frag in
            guard line < results.count, let text = results[line].display else { return nil }
            return Slot(line: line, rect: NSRect(x: left, y: frag.minY, width: right - left, height: frag.height), text: text)
        }
    }

    /// Results live in a transparent subview so they paint above the text view's own text layers.
    private lazy var overlay: ResultsOverlay = {
        let v = ResultsOverlay(frame: bounds)
        v.owner = self
        v.autoresizingMask = [.width, .height]
        addSubview(v)
        return v
    }()

    func drawResults(_ dirtyRect: NSRect) {
        let t = style.theme
        if style.highlightLine, let lm = layoutManager, window?.firstResponder === self {
            // Soft band behind the line holding the cursor.
            let loc = min(selectedRange().location, (string as NSString).length)
            var rect: NSRect
            if loc == (string as NSString).length, loc == 0 || (string as NSString).character(at: loc - 1) == 10 {
                rect = lm.extraLineFragmentRect
            } else {
                let idx = lm.glyphIndexForCharacter(at: max(0, min(loc, (string as NSString).length - 1)))
                rect = lm.lineFragmentRect(forGlyphAt: idx, effectiveRange: nil)
            }
            if rect.height > 0 {
                rect.origin.y += textContainerOrigin.y
                t.text.withAlphaComponent(0.045).setFill()
                NSRect(x: 0, y: rect.minY, width: bounds.width, height: rect.height).fill()
            }
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.lineBreakMode = .byTruncatingHead
        for s in slots() where s.rect.intersects(dirtyRect) {
            let copied = s.line == copiedLine
            if s.line == hoverLine || copied {
                let size = (s.text as NSString).size(withAttributes: [.font: baseFont])
                let w = min(s.rect.width, size.width) + 12
                let bg = NSRect(x: s.rect.maxX - w + 6, y: s.rect.minY + 1, width: w, height: s.rect.height - 2)
                t.result.withAlphaComponent(copied ? 0.22 : 0.12).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: t.result, .paragraphStyle: para]
            (copied ? "Copied" : s.text).draw(with: s.rect, options: [.usesLineFragmentOrigin], attributes: attrs)
        }
    }

    // MARK: Click to copy

    private func slot(at event: NSEvent) -> Slot? {
        let p = convert(event.locationInWindow, from: nil)
        return slots().first { $0.rect.contains(p) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let s = slot(at: event) else { return super.mouseDown(with: event) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText?(s.line) ?? s.text, forType: .string)
        copiedLine = s.line
        refreshOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            if self?.copiedLine == s.line { self?.copiedLine = nil; self?.refreshOverlay() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self && $0.userInfo?["results"] != nil }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: ["results": true]))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let line = slot(at: event)?.line
        if line != hoverLine { hoverLine = line; refreshOverlay() }
        if line != nil { NSCursor.pointingHand.set() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoverLine != nil { hoverLine = nil; refreshOverlay() }
    }

    // MARK: Syntax colouring

    func applyHighlighting() {
        guard let storage = textStorage, let lm = layoutManager else { return }
        let t = style.theme
        let font = baseFont
        let bold = FontCatalog.font(style.fontID, size: style.fontSize, weight: .bold)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .paragraphStyle: paragraph, .foregroundColor: t.text], range: full)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        var offset = 0
        for (i, line) in string.components(separatedBy: "\n").enumerated() {
            let len = (line as NSString).length
            defer { offset += len + 1 }
            guard i < results.count, len > 0 else { continue }
            let r = results[i]
            let lineRange = NSRange(location: offset, length: len)
            if r.kind == .header { storage.addAttribute(.font, value: bold, range: lineRange) }
            if r.kind == .text { lm.addTemporaryAttribute(.foregroundColor, value: t.secondary, forCharacterRange: lineRange) }
            for span in r.spans where span.range.upperBound <= len {
                lm.addTemporaryAttribute(.foregroundColor, value: t.color(span.style),
                                         forCharacterRange: NSRange(location: offset + span.range.lowerBound, length: span.range.count))
            }
        }
        storage.endEditing()
        typingAttributes = [.font: font, .foregroundColor: t.text, .paragraphStyle: paragraph]
    }
}

struct EditorView: NSViewRepresentable {
    let library: Library
    var style: EditorStyle

    func makeCoordinator() -> Coordinator { Coordinator(library: library) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        lm.addTextContainer(container)

        let tv = CalcTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 22, height: 10)
        tv.drawsBackground = true
        tv.delegate = context.coordinator
        tv.copyText = { [weak library] line in MainActor.assumeIsolated { library?.copyText(line: line) } }
        tv.string = library.text
        tv.style = style
        tv.applyStyle()
        tv.results = library.results
        context.coordinator.generation = library.loadGeneration

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.documentView = tv
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll.contentView,
                                               queue: .main) { _ in tv.setFrameSize(tv.frame.size) }
        library.textView = tv
        context.coordinator.textView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? CalcTextView else { return }
        tv.style = style
        if context.coordinator.generation != library.loadGeneration {
            context.coordinator.generation = library.loadGeneration
            if tv.string != library.text {
                tv.string = library.text
                tv.undoManager?.removeAllActions()
                tv.setSelectedRange(NSRange(location: 0, length: 0))
            }
        }
        tv.results = library.results
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let library: Library
        weak var textView: CalcTextView?
        var generation = -1
        init(library: Library) { self.library = library }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? CalcTextView else { return }
            MainActor.assumeIsolated {
                library.edit(tv.string)
                // Push results straight to the view rather than waiting for SwiftUI to schedule an update.
                tv.results = library.results
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let loc = tv.selectedRange().location
            let prefix = (tv.string as NSString).substring(to: min(loc, (tv.string as NSString).length))
            let line = prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            MainActor.assumeIsolated { if library.cursorLine != line { library.cursorLine = line } }
        }
    }
}

final class ResultsOverlay: NSView {
    weak var owner: CalcTextView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { owner?.drawResults(dirtyRect) }
}
