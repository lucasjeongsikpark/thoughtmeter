import Foundation

/// Decides whether a keyboard event counts as one Thought Input keystroke.
///
/// Rules (see PRIVACY.md and README "What Thought Input means"):
/// - Every `keyDown` counts, including auto-repeat.
/// - `keyUp` never reaches this type (the event source does not observe it).
/// - A modifier counts when it transitions into the pressed state
///   (a flag bit that was clear becomes set). Releases do not count.
/// - Caps Lock is a toggle at the flag level: each physical press flips the
///   bit, so any Caps Lock bit change counts as one keystroke.
/// - Fn/Globe is never counted (see ModifierFlags.counted).
///
/// Not thread-safe on its own; callers serialize access (InputTracker does).
public final class KeystrokeCounter {
    private var previousModifiers: ModifierFlags = []

    public init() {}

    /// Returns true if this event represents one countable keystroke.
    /// Must be called for every event (even while paused) so modifier state
    /// stays consistent.
    public func shouldCount(_ event: KeyEventKind) -> Bool {
        switch event {
        case .keyDown:
            return true
        case .flagsChanged(let raw):
            let current = ModifierFlags(deviceIndependent: raw)
            let previous = previousModifiers
            previousModifiers = current

            let capsToggled = current.contains(.capsLock) != previous.contains(.capsLock)
            if capsToggled { return true }

            let newlyPressed = current.subtracting(previous).subtracting(.capsLock)
            return !newlyPressed.isEmpty
        }
    }

    /// Forget held-modifier state (used when the event tap restarts).
    public func reset() {
        previousModifiers = []
    }
}
