import XCTest
@testable import AtlasTuneCore

final class UndoStackTests: XCTestCase {
    func testCommitUndoRedo() {
        var stack = UndoStack(initial: 0)
        stack.commit(1)
        stack.commit(2)
        XCTAssertEqual(stack.current, 2)
        XCTAssertTrue(stack.canUndo)

        XCTAssertEqual(stack.undo(), 1)
        XCTAssertEqual(stack.undo(), 0)
        XCTAssertNil(stack.undo())
        XCTAssertFalse(stack.canUndo)

        XCTAssertEqual(stack.redo(), 1)
        XCTAssertEqual(stack.redo(), 2)
        XCTAssertNil(stack.redo())
    }

    func testCommitClearsRedoBranch() {
        var stack = UndoStack(initial: 0)
        stack.commit(1)
        _ = stack.undo()
        stack.commit(99)
        XCTAssertFalse(stack.canRedo)
        XCTAssertEqual(stack.current, 99)
    }

    func testUnlimitedHistory() {
        var stack = UndoStack(initial: 0)
        for i in 1...1000 { stack.commit(i) }
        XCTAssertEqual(stack.undoCount, 1000)
        for _ in 0..<1000 { _ = stack.undo() }
        XCTAssertEqual(stack.current, 0)
    }
}
