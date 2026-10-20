import AppKit
import SwiftUI
import TallyEngine

/// Plain-text editor that draws each line's result right-aligned in a column, Numi-style.
final class CalcTextView: NSTextView {
    private(set) var results: [LineResult] = []
    private var resultsVersion = -1

    /// Applies new results once per evaluation (both the typing path and SwiftUI updates call this).
    func setResults(_ r: [LineResult], version: Int) {
        guard version != resultsVersion else { return }
        resultsVersion = version
        results = r
        applyHighlighting()
        refreshOverlay()
    }
    var style = EditorStyle(theme: .system, fontID: "system", fontSize: 15, lineSpacing: 5, resultFraction: 0.4,
                            highlightLine: true) {
        didSet { if style != oldValue { applyStyle() } }
    }
    /// Text to put on the clipboard when a result is clicked (lets settings choose number-only copies).
    var copyText: ((Int) -> String?)?
    /// Strips results from pasted text, given the document above the paste point.
    var cleanPaste: ((String, String) -> String)?

    /// The selection exactly as typed, so Tally-to-Tally pastes don't need any result stripping.
    static let rawType = NSPasteboard.PasteboardType("com.kengomes.tally.source")

    private var copiedLine: Int?
    /// 1 while "Copied" shows, easing to 0 as the result fades back.
    private var copyFade: CGFloat = 0
    private var fadeTimer: Timer?
    private var hoverLine: Int?
    var baseFont: NSFont { FontCatalog.font(style.fontID, size: style.fontSize) }
    weak var lineNumberRuler: LineNumberRuler?
    private var paragraph = NSParagraphStyle()

    var resultColumnWidth: CGFloat { CalcTextContainer.columnWidth(bounds.width, style.resultFraction) }

    func applyStyle() {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.lineSpacing
        paragraph = p
        let t = style.theme
        backgroundColor = t.background
        insertionPointColor = t.text
        selectedTextAttributes = [.backgroundColor: t.selection]
        defaultParagraphStyle = p
        if let tc = textContainer as? CalcTextContainer, tc.resultFraction != style.resultFraction {
            tc.resultFraction = style.resultFraction
            layoutManager?.textContainerChangedGeometry(tc)
        }
        applyHighlighting()
        refreshOverlay()
        needsUpdateLineHighlight = true
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        overlay.frame = bounds
        needsUpdateLineHighlight = true
        // Results are right-aligned, so they must be redrawn (not stretched or shifted) on every frame
        // of a resize or sidebar animation.
        overlay.needsDisplay = true
    }

    override func didChangeText() {
        cachedLines = nil
        super.didChangeText()
        refreshOverlay()
        refreshCurrentLine()
    }

    override var string: String {
        get { super.string }
        set { super.string = newValue; cachedLines = nil }
    }

    /// Range of each line (without its newline), computed once per text change instead of on every
    /// draw — the overlay redraws on every frame of a sidebar animation or window resize.
    private var cachedLines: [NSRange]?
    var lineRangesForEditing: [NSRange] { lineRanges }
    private var lineRanges: [NSRange] {
        if let c = cachedLines { return c }
        let ns = string as NSString
        var out: [NSRange] = []
        var start = 0
        while true {
            let nl = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
            if nl.location == NSNotFound { out.append(NSRange(location: start, length: ns.length - start)); break }
            out.append(NSRange(location: start, length: nl.location - start))
            start = nl.location + 1
        }
        cachedLines = out
        return out
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        refreshCurrentLine()
        lineNumberRuler?.needsDisplay = true
    }

    // MARK: Current line
    //
    // Modelled on CotEditor: mark the highlight dirty on any change, repaint the old band plus the
    // visible area, and measure the new band at draw time — after AppKit has settled the layout.

    private var lineHighlightRects: [NSRect] = []
    private var needsUpdateLineHighlight = true {
        didSet {
            guard needsUpdateLineHighlight else { return }
            (lineHighlightRects + [visibleRect]).forEach { setNeedsDisplay($0, avoidAdditionalLayout: true) }
        }
    }

    private func refreshCurrentLine() { needsUpdateLineHighlight = true }

    /// Bands covering every visual row of each line that holds a cursor or selection.
    private func computeLineHighlightRects() -> [NSRect] {
        guard let lm = layoutManager else { return [] }
        let ns = string as NSString
        var lines: [NSRange] = []
        for value in selectedRanges {
            let line = ns.lineRange(for: value.rangeValue)
            if let last = lines.last, NSMaxRange(last) >= line.location { lines[lines.count - 1] = NSUnionRange(last, line) }
            else { lines.append(line) }
        }
        return lines.compactMap { range -> NSRect? in
            var rect: NSRect
            if ns.length == 0 || (range.location >= ns.length && lm.extraLineFragmentTextContainer != nil) {
                rect = lm.extraLineFragmentRect
            } else {
                let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let lower = lm.isValidGlyphIndex(glyphs.location) ? glyphs.location : max(0, glyphs.location - 1)
                var effective = NSRange()
                rect = lm.lineFragmentRect(forGlyphAt: lower, effectiveRange: &effective)
                if glyphs.length > 0, !NSLocationInRange(NSMaxRange(glyphs) - 1, effective) {
                    rect = rect.union(lm.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil))
                }
            }
            guard rect.height > 0 else { return nil }
            return NSRect(x: 0, y: rect.minY + textContainerOrigin.y, width: bounds.width, height: rect.height)
        }
    }

    /// Draws under the glyphs (the hook CotEditor uses), so the highlight never tints the text.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard style.highlightLine, window?.firstResponder === self else { return }
        if needsUpdateLineHighlight {
            lineHighlightRects = computeLineHighlightRects()
            needsUpdateLineHighlight = false
        }
        style.theme.text.withAlphaComponent(0.05).setFill()
        for band in lineHighlightRects where band.intersects(rect) { band.intersection(rect).fill() }
    }

    override func becomeFirstResponder() -> Bool {
        defer { refreshCurrentLine() }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { refreshCurrentLine() }
        return super.resignFirstResponder()
    }

    private func refreshOverlay() {
        overlay.needsDisplay = true
        lineNumberRuler?.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Result layout

    private struct Slot { let line: Int; let rect: NSRect; let text: String }

    /// Line rectangles for the lines currently on screen only.
    func lineRects(includeEmpty: Bool = false) -> [(line: Int, range: NSRange, rect: NSRect)] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        var visible = visibleRect
        visible.origin.y -= textContainerOrigin.y
        // Lays out just the visible rect if needed (cheap with non-contiguous layout).
        let glyphsOnScreen = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charsOnScreen = lm.characterRange(forGlyphRange: glyphsOnScreen, actualGlyphRange: nil)
        let lines = lineRanges
        // First line that ends at or after the visible range (binary search).
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if NSMaxRange(lines[mid]) < charsOnScreen.location { lo = mid + 1 } else { hi = mid }
        }
        var out: [(Int, NSRange, NSRect)] = []
        for i in lo..<lines.count {
            let range = lines[i]
            if range.location > NSMaxRange(charsOnScreen) { break }
            var frag: NSRect
            if range.length > 0 {
                let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                frag = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            } else if includeEmpty {
                // Empty line: its newline glyph, or the extra fragment after a trailing newline.
                if range.location < (string as NSString).length {
                    frag = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: range.location), effectiveRange: nil)
                } else {
                    frag = lm.extraLineFragmentRect
                    if frag.height == 0 { continue }
                }
            } else {
                continue
            }
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
        v.wantsLayer = true
        v.layerContentsRedrawPolicy = .duringViewResize
        v.autoresizingMask = [.width, .height]
        addSubview(v)
        return v
    }()

    func drawResults(_ dirtyRect: NSRect) {
        let t = style.theme
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.lineBreakMode = .byTruncatingHead
        for s in slots() where s.rect.intersects(dirtyRect) {
            let fade = s.line == copiedLine ? copyFade : 0
            if s.line == hoverLine || fade > 0 {
                // Wrap the text itself, not the whole line fragment (which includes the line spacing below it).
                let shown = fade > 0.5 ? "Copied" : s.text
                let textWidth = min(s.rect.width, (shown as NSString).size(withAttributes: [.font: baseFont]).width)
                let textHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)
                let padX: CGFloat = 6, padY: CGFloat = 2
                let bg = NSRect(x: s.rect.maxX - textWidth - padX, y: s.rect.minY - padY,
                                width: textWidth + padX * 2, height: textHeight + padY * 2)
                t.result.withAlphaComponent((s.line == hoverLine ? 0.12 : 0) + 0.12 * fade).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
            }
            func draw(_ text: String, _ alpha: CGFloat) {
                guard alpha > 0.01 else { return }
                let attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: t.result.withAlphaComponent(alpha),
                                                            .paragraphStyle: para]
                text.draw(with: s.rect, options: [.usesLineFragmentOrigin], attributes: attrs)
            }
            draw(s.text, 1 - fade)
            draw("Copied", fade)
        }
    }

    // MARK: Copy & paste

    /// Like Numi: copying whole lines carries their results ("rent * 12 = $17,400").
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return super.copy(sender) }
        let ns = string as NSString
        let raw = ns.substring(with: range)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(withResults(range), forType: .string)
        pb.setString(raw, forType: Self.rawType)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        copy(sender)
        insertText("", replacementRange: selectedRange())
    }

    private func withResults(_ range: NSRange) -> String {
        let ns = string as NSString
        let raw = ns.substring(with: range)
        // A fragment inside one line copies as plain text.
        let first = ns.lineRange(for: NSRange(location: range.location, length: 0))
        if !raw.contains("\n") && NSMaxRange(range) < NSMaxRange(first) - (ns.substring(with: first).hasSuffix("\n") ? 1 : 0) {
            return raw
        }
        var out: [String] = []
        var offset = 0
        for (i, line) in string.components(separatedBy: "\n").enumerated() {
            let lineRange = NSRange(location: offset, length: (line as NSString).length)
            offset += lineRange.length + 1
            let part = NSIntersectionRange(lineRange, range)
            let touches = part.length > 0 || (lineRange.length == 0 && lineRange.location >= range.location
                                                  && lineRange.location < NSMaxRange(range))
            guard touches else { continue }
            var text = ns.substring(with: part)
            if NSMaxRange(part) == NSMaxRange(lineRange), i < results.count, let d = results[i].display {
                text += " = " + d
            }
            out.append(text)
        }
        return out.joined(separator: "\n")
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let text: String
        if let raw = pb.string(forType: Self.rawType) {
            text = raw
        } else if let s = pb.string(forType: .string) {
            let ns = string as NSString
            let lineStart = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0)).location
            text = cleanPaste?(s, ns.substring(to: lineStart).trimmingCharacters(in: .newlines)) ?? s
        } else {
            return super.paste(sender)
        }
        insertText(text, replacementRange: selectedRange())
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
        animateCopy(to: 1, duration: 0.12) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard self?.copiedLine == s.line else { return }
                self?.animateCopy(to: 0, duration: 0.3) { self?.copiedLine = nil }
            }
        }
    }

    private func animateCopy(to target: CGFloat, duration: TimeInterval, then done: @escaping () -> Void) {
        fadeTimer?.invalidate()
        let start = copyFade, began = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let p = min(1, Date().timeIntervalSince(began) / duration)
            let eased = 1 - pow(1 - p, 3)
            self.copyFade = start + (target - start) * eased
            self.overlay.needsDisplay = true
            if p >= 1 { timer.invalidate(); done() }
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
        for (i, lineRange) in lineRanges.enumerated() {
            let len = lineRange.length
            let offset = lineRange.location
            guard i < results.count, len > 0 else { continue }
            let r = results[i]
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
        // Only lay out what's on screen (as CotEditor does), so long calculations open and scroll fast.
        lm.allowsNonContiguousLayout = true
        // Width follows the text view through normal autoresizing; the container itself keeps text out of
        // the results column, so a resize or sidebar animation is a single AppKit layout pass per frame.
        let container = CalcTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.resultFraction = style.resultFraction
        lm.addTextContainer(container)

        let tv = CalcTextView(frame: .zero, textContainer: container)
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
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 22, height: 10)
        tv.drawsBackground = true
        tv.delegate = context.coordinator
        tv.copyText = { [weak library] line in MainActor.assumeIsolated { library?.copyText(line: line) } }
        tv.cleanPaste = { [weak library] text, context in
            MainActor.assumeIsolated { library?.cleanPaste(text, context: context) ?? text }
        }
        tv.string = library.text
        tv.style = style
        tv.applyStyle()
        tv.setResults(library.results, version: library.resultsVersion)
        context.coordinator.generation = library.loadGeneration

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.documentView = tv
        let ruler = LineNumberRuler(scrollView: scroll, editor: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = style.lineNumbers
        tv.lineNumberRuler = ruler
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                               queue: .main) { [weak ruler] _ in ruler?.needsDisplay = true }
        scroll.contentView.postsFrameChangedNotifications = true
        library.textView = tv
        context.coordinator.textView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? CalcTextView else { return }
        if scroll.rulersVisible != style.lineNumbers { scroll.rulersVisible = style.lineNumbers }
        (scroll.verticalRulerView as? LineNumberRuler)?.updateThickness()
        tv.style = style
        if context.coordinator.generation != library.loadGeneration {
            context.coordinator.generation = library.loadGeneration
            if tv.string != library.text {
                tv.string = library.text
                tv.undoManager?.removeAllActions()
                tv.setSelectedRange(NSRange(location: 0, length: 0))
                tv.scrollToBeginningOfDocument(nil)
            }
        }
        tv.setResults(library.results, version: library.resultsVersion)
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
                tv.setResults(library.results, version: library.resultsVersion)
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

/// Text container that reserves the right-hand results column, so the text view can simply track its
/// scroll view's width and AppKit handles every resize in one layout pass.
final class CalcTextContainer: NSTextContainer {
    var resultFraction: CGFloat = 0.4
    /// Horizontal inset of the text view, so the column matches what the overlay draws.
    var inset: CGFloat = 22

    static func columnWidth(_ viewWidth: CGFloat, _ fraction: CGFloat) -> CGFloat {
        max(120, viewWidth * fraction)
    }

    override var isSimpleRectangularTextContainer: Bool { false }

    override func lineFragmentRect(forProposedRect proposedRect: NSRect, at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<NSRect>?) -> NSRect {
        var rect = super.lineFragmentRect(forProposedRect: proposedRect, at: characterIndex,
                                          writingDirection: baseWritingDirection, remaining: remainingRect)
        let usable = size.width - Self.columnWidth(size.width + inset * 2, resultFraction)
        rect.size.width = max(80, min(rect.width, usable))
        return rect
    }
}

// MARK: - Line editing (move, duplicate, delete, toggle comment)

extension CalcTextView {
    /// Lines touched by the selection (a selection ending at the very start of a line doesn't include it).
    private func selectedLines() -> ClosedRange<Int> {
        let lines = lineIndex
        let sel = selectedRange()
        let first = lines(sel.location)
        var endLoc = NSMaxRange(sel)
        if sel.length > 0, endLoc > sel.location, (string as NSString).character(at: endLoc - 1) == 10 { endLoc -= 1 }
        return first...max(first, lines(endLoc))
    }

    /// Index of the line containing a character offset (binary search over cached line ranges).
    private var lineIndex: (Int) -> Int {
        let ranges = lineRangesForEditing
        return { loc in
            var lo = 0, hi = ranges.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if ranges[mid].location <= loc { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }
    }

    private func lineText(_ i: Int) -> String { (string as NSString).substring(with: lineRangesForEditing[i]) }

    /// Replaces `range` as one undoable edit and selects `selection` afterwards.
    private func replace(_ range: NSRange, with text: String, select selection: NSRange, action: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        undoManager?.setActionName(action)
        let length = (string as NSString).length
        let loc = min(max(0, selection.location), length)
        setSelectedRange(NSRange(location: loc, length: min(selection.length, length - loc)))
        scrollRangeToVisible(selectedRange())
    }

    private func span(_ lines: ClosedRange<Int>) -> NSRange {
        let r = lineRangesForEditing
        return NSRange(location: r[lines.lowerBound].location,
                       length: NSMaxRange(r[lines.upperBound]) - r[lines.lowerBound].location)
    }

    @objc func moveLinesUp(_ sender: Any?) {
        let lines = selectedLines()
        guard lines.lowerBound > 0 else { return }
        let above = lineText(lines.lowerBound - 1)
        let block = lines.map(lineText)
        let shift = (above as NSString).length + 1
        let sel = selectedRange()
        replace(span(lines.lowerBound - 1...lines.upperBound), with: (block + [above]).joined(separator: "\n"),
                select: NSRange(location: sel.location - shift, length: sel.length), action: "Move Line Up")
    }

    @objc func moveLinesDown(_ sender: Any?) {
        let lines = selectedLines()
        guard lines.upperBound < lineRangesForEditing.count - 1 else { return }
        let below = lineText(lines.upperBound + 1)
        let block = lines.map(lineText)
        let shift = (below as NSString).length + 1
        let sel = selectedRange()
        replace(span(lines.lowerBound...lines.upperBound + 1), with: ([below] + block).joined(separator: "\n"),
                select: NSRange(location: sel.location + shift, length: sel.length), action: "Move Line Down")
    }

    @objc func duplicateLines(_ sender: Any?) {
        let lines = selectedLines()
        let block = lines.map(lineText).joined(separator: "\n")
        let shift = (block as NSString).length + 1
        let sel = selectedRange()
        replace(span(lines), with: block + "\n" + block,
                select: NSRange(location: sel.location + shift, length: sel.length), action: "Duplicate Line")
    }

    @objc func deleteLines(_ sender: Any?) {
        let lines = selectedLines()
        let r = lineRangesForEditing
        let ns = string as NSString
        var range: NSRange
        if lines.upperBound < r.count - 1 {
            range = NSRange(location: r[lines.lowerBound].location, length: r[lines.upperBound + 1].location - r[lines.lowerBound].location)
        } else if lines.lowerBound > 0 {
            let start = NSMaxRange(r[lines.lowerBound - 1])
            range = NSRange(location: start, length: ns.length - start)
        } else {
            range = NSRange(location: 0, length: ns.length)
        }
        let caret = lines.upperBound < r.count - 1 ? range.location : (lines.lowerBound > 0 ? r[lines.lowerBound - 1].location : 0)
        replace(range, with: "", select: NSRange(location: caret, length: 0), action: "Delete Line")
    }

    /// Adds "// " to every line, or removes it if all non-empty lines are already commented.
    @objc func toggleLineComment(_ sender: Any?) {
        let lines = selectedLines()
        let texts = lines.map(lineText)
        func indentEnd(_ s: String) -> String.Index { s.firstIndex { $0 != " " && $0 != "\t" } ?? s.endIndex }
        let content = texts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let uncomment = !content.isEmpty && content.allSatisfy { $0[indentEnd($0)...].hasPrefix("//") }
        let updated = texts.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let i = indentEnd(line)
            if uncomment {
                var rest = line[i...].dropFirst(2)
                if rest.hasPrefix(" ") { rest = rest.dropFirst() }
                return String(line[..<i]) + rest
            }
            return String(line[..<i]) + "// " + line[i...]
        }
        let range = span(lines)
        let joined = updated.joined(separator: "\n")
        let sel = selectedRange()
        let newSelection: NSRange
        if sel.length == 0, lines.count == 1 {
            // Keep the caret on the same character.
            let delta = (joined as NSString).length - range.length
            newSelection = NSRange(location: max(range.location, sel.location + delta), length: 0)
        } else {
            newSelection = NSRange(location: range.location, length: (joined as NSString).length)
        }
        replace(range, with: joined, select: newSelection, action: uncomment ? "Uncomment" : "Comment")
    }
}

// MARK: - Line numbers

/// Line-number gutter, CotEditor-style: an NSRulerView on the scroll view that draws numbers for the
/// visible lines only.
final class LineNumberRuler: NSRulerView {
    private weak var editor: CalcTextView?

    init(scrollView: NSScrollView, editor: CalcTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        clipsToBounds = true
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var numberFont: NSFont {
        let size = (editor?.style.fontSize ?? 15) * 0.8
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    func updateThickness() {
        let lines = editor?.lineRangesForEditing.count ?? 1
        let digits = max(2, String(lines).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        let thickness = ceil(CGFloat(digits) * digitWidth + 18)
        if abs(ruleThickness - thickness) > 0.5 { ruleThickness = thickness }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Since macOS 14 views don't clip by default; never paint outside the gutter.
        let area = dirtyRect.intersection(bounds)
        (editor?.style.theme.background ?? .textBackgroundColor).setFill()
        area.fill()
        drawHashMarksAndLabels(in: area)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = editor else { return }
        updateThickness()
        let theme = tv.style.theme
        let ns = tv.string as NSString
        let caretLine: Int = {
            let loc = min(tv.selectedRange().location, ns.length)
            let ranges = tv.lineRangesForEditing
            return ranges.lastIndex { $0.location <= loc } ?? 0
        }()
        let font = numberFont
        let textFont = tv.baseFont
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        for (line, _, frag) in tv.lineRects(includeEmpty: true) {
            let top = convert(NSPoint(x: 0, y: frag.minY), from: tv).y
            // Align the number's baseline with the text's first line.
            let y = top + (textFont.ascender - font.ascender)
            let r = NSRect(x: 0, y: y, width: ruleThickness - 9, height: frag.height)
            guard r.intersects(rect.insetBy(dx: 0, dy: -frag.height)) else { continue }
            let color = line == caretLine ? theme.text.withAlphaComponent(0.85) : theme.comment
            ("\(line + 1)" as NSString).draw(with: r, options: [.usesLineFragmentOrigin],
                                              attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        }
    }
}
