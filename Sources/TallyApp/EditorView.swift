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
        cachedLines = nil
        super.didChangeText()
        refreshOverlay()
    }

    override var string: String {
        get { super.string }
        set { super.string = newValue; cachedLines = nil }
    }

    /// Range of each line (without its newline), computed once per text change instead of on every
    /// draw — the overlay redraws on every frame of a sidebar animation or window resize.
    private var cachedLines: [NSRange]?
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
        if style.highlightLine { overlay.needsDisplay = true }
    }

    private func refreshOverlay() {
        overlay.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Result layout

    private struct Slot { let line: Int; let rect: NSRect; let text: String }

    /// Line rectangles for the lines currently on screen only.
    private func lineRects() -> [(line: Int, range: NSRange, rect: NSRect)] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        var visible = visibleRect
        visible.origin.y -= textContainerOrigin.y
        var glyphsOnScreen = lm.glyphRange(forBoundingRectWithoutAdditionalLayout: visible, in: tc)
        if glyphsOnScreen.length == 0 { glyphsOnScreen = lm.glyphRange(forBoundingRect: visible, in: tc) }
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
            guard range.length > 0 else { continue }
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
            let fade = s.line == copiedLine ? copyFade : 0
            if s.line == hoverLine || fade > 0 {
                let size = (s.text as NSString).size(withAttributes: [.font: baseFont])
                let w = min(s.rect.width, size.width) + 12
                let bg = NSRect(x: s.rect.maxX - w + 6, y: s.rect.minY + 1, width: w, height: s.rect.height - 2)
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
