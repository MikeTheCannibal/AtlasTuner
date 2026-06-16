import Foundation

/// A generic, unlimited snapshot-based undo/redo stack.
///
/// Each committed state is retained, satisfying the spec's "unlimited undo history". Because
/// ``CalibrationTable`` and ``BINImage`` are copy-on-write value types, retaining snapshots is
/// cheap until the underlying storage actually diverges.
public struct UndoStack<State: Sendable>: Sendable {
    private var past: [State] = []
    private var future: [State] = []
    public private(set) var current: State

    public init(initial: State) {
        self.current = initial
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoCount: Int { past.count }
    public var redoCount: Int { future.count }

    /// Commit a new state, making it current and clearing the redo branch.
    public mutating func commit(_ state: State) {
        past.append(current)
        current = state
        future.removeAll(keepingCapacity: true)
    }

    @discardableResult
    public mutating func undo() -> State? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        current = previous
        return current
    }

    @discardableResult
    public mutating func redo() -> State? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        current = next
        return current
    }
}
