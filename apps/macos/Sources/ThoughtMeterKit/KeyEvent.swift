import Foundation

/// A keyboard event reduced to the minimum information ThoughtMeter needs.
///
/// Privacy invariant: this type carries NO key code and NO character data.
/// For regular keys we only know "a key went down". For modifier changes we
/// carry the modifier flag bitmask (which modifiers are currently held) so
/// that down-transitions can be detected in memory; the bitmask is never
/// persisted or logged.
public enum KeyEventKind: Equatable {
    /// A non-modifier key entered the pressed state (includes auto-repeat).
    case keyDown(isAutoRepeat: Bool)
    /// The set of held modifier keys changed. `rawFlags` mirrors
    /// CGEventFlags' device-independent bits.
    case flagsChanged(rawFlags: UInt64)
}

/// Device-independent modifier flag bits, matching CGEventFlags values.
/// Defined locally so ThoughtMeterKit stays testable without CoreGraphics.
public struct ModifierFlags: OptionSet, Equatable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let capsLock = ModifierFlags(rawValue: 0x0001_0000) // maskAlphaShift
    public static let shift    = ModifierFlags(rawValue: 0x0002_0000) // maskShift
    public static let control  = ModifierFlags(rawValue: 0x0004_0000) // maskControl
    public static let option   = ModifierFlags(rawValue: 0x0008_0000) // maskAlternate
    public static let command  = ModifierFlags(rawValue: 0x0010_0000) // maskCommand

    /// Modifiers ThoughtMeter counts. Fn/Globe (maskSecondaryFn) is excluded:
    /// arrow and function keys set that bit implicitly, which would double
    /// count them (one flagsChanged + one keyDown per press).
    public static let counted: ModifierFlags = [.capsLock, .shift, .control, .option, .command]

    /// Keep only the bits ThoughtMeter cares about.
    public init(deviceIndependent raw: UInt64) {
        self.init(rawValue: raw & ModifierFlags.counted.rawValue)
    }
}

/// Abstraction over the global keyboard event stream so counting logic can be
/// tested without creating a real CGEventTap.
public protocol KeyEventSource: AnyObject {
    /// Called for every observed keyboard event. Must be cheap.
    var onEvent: ((KeyEventKind) -> Void)? { get set }
    func start() throws
    func stop()
}
