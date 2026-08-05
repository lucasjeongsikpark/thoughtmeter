import Foundation
import CoreGraphics
import ThoughtMeterKit

/// Listen-only CGEventTap for keyDown + flagsChanged, running its own thread.
///
/// Requires the Input Monitoring permission. The callback forwards a reduced
/// KeyEventKind (no key codes, no characters — see KeyEvent.swift) to
/// InputTracker and returns immediately. keyUp is never observed.
final class EventTapSource: KeyEventSource {
    enum TapError: Error, CustomStringConvertible {
        case creationFailed
        var description: String {
            "Could not create the keyboard event listener. Input Monitoring permission is probably missing."
        }
    }

    var onEvent: ((KeyEventKind) -> Void)?

    fileprivate var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    func start() throws {
        guard tap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                 | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw TapError.creationFailed
        }
        tap = createdTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0)
        runLoopSource = source

        let tapThread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        tapThread.name = "org.thoughtmeter.eventtap"
        tapThread.qualityOfService = .userInteractive
        tapThread.start()
        thread = tapThread
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoopSource = nil
        runLoop = nil
        thread = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

/// C-convention callback. Does the minimum: map the event type and forward.
/// No key codes are read; flagsChanged forwards only the modifier bitmask.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return nil }
    let source = Unmanaged<EventTapSource>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .keyDown:
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        source.onEvent?(.keyDown(isAutoRepeat: isRepeat))
    case .flagsChanged:
        source.onEvent?(.flagsChanged(rawFlags: event.flags.rawValue))
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // macOS disables slow taps; ours is fast, but recover regardless.
        source.reenable()
    default:
        break
    }
    return nil // listen-only tap; return value is ignored
}
