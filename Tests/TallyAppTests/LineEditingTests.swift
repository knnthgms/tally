import AppKit
import XCTest
@testable import TallyApp

@MainActor
final class LineEditingTests: XCTestCase {
    private func editor(_ text: String, caret: Int, length: Int = 0) -> CalcTextView {
        let tv = CalcTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        tv.string = text
        tv.setSelectedRange(NSRange(location: caret, length: length))
        return tv
    }

    func testMoveLineUpAndDown() {
        let tv = editor("a = 1\nb = 2\nc = 3", caret: 7) // on "b = 2"
        tv.moveLinesUp(nil)
        XCTAssertEqual(tv.string, "b = 2\na = 1\nc = 3")
        XCTAssertEqual(tv.selectedRange().location, 1)
        tv.moveLinesDown(nil)
        tv.moveLinesDown(nil)
        XCTAssertEqual(tv.string, "a = 1\nc = 3\nb = 2")
        tv.moveLinesDown(nil) // already last: no change
        XCTAssertEqual(tv.string, "a = 1\nc = 3\nb = 2")
    }

    func testMoveMultipleSelectedLines() {
        let tv = editor("1\n2\n3\n4", caret: 2, length: 3) // "2\n3"
        tv.moveLinesDown(nil)
        XCTAssertEqual(tv.string, "1\n4\n2\n3")
    }

    func testDuplicateAndDelete() {
        let tv = editor("x = 5\ny = x * 2", caret: 2)
        tv.duplicateLines(nil)
        XCTAssertEqual(tv.string, "x = 5\nx = 5\ny = x * 2")
        XCTAssertEqual(tv.selectedRange().location, 8)
        tv.deleteLines(nil)
        XCTAssertEqual(tv.string, "x = 5\ny = x * 2")
        tv.setSelectedRange(NSRange(location: 8, length: 0)) // last line
        tv.deleteLines(nil)
        XCTAssertEqual(tv.string, "x = 5")
        tv.deleteLines(nil)
        XCTAssertEqual(tv.string, "")
    }

    func testToggleComment() {
        let tv = editor("rent = 100\n\n  tip = 5", caret: 0, length: 20)
        tv.toggleLineComment(nil)
        XCTAssertEqual(tv.string, "// rent = 100\n\n  // tip = 5")
        tv.toggleLineComment(nil)
        XCTAssertEqual(tv.string, "rent = 100\n\n  tip = 5")
        let one = editor("a = 1", caret: 3)
        one.toggleLineComment(nil)
        XCTAssertEqual(one.string, "// a = 1")
        XCTAssertEqual(one.selectedRange().location, 6)
    }

    func testUndoRestoresMove() {
        let tv = editor("a\nb", caret: 2)
        tv.allowsUndo = true
        let undo = UndoManager()
        let host = UndoHost(undo)
        tv.delegate = host
        tv.moveLinesUp(nil)
        XCTAssertEqual(tv.string, "b\na")
        undo.undo()
        XCTAssertEqual(tv.string, "a\nb")
        _ = host
    }
}

private final class UndoHost: NSObject, NSTextViewDelegate {
    let manager: UndoManager
    init(_ m: UndoManager) { manager = m }
    func undoManager(for view: NSTextView) -> UndoManager? { manager }
}
