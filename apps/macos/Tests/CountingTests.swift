import Foundation
import ThoughtMeterKit

// Flag bit helpers matching CGEventFlags device-independent masks.
private let capsBit: UInt64 = 0x0001_0000
private let shiftBit: UInt64 = 0x0002_0000
private let controlBit: UInt64 = 0x0004_0000
private let optionBit: UInt64 = 0x0008_0000
private let commandBit: UInt64 = 0x0010_0000
private let fnBit: UInt64 = 0x0080_0000

let keystrokeCounterTests: [TC] = [
    TC("ordinary keyDown counts") { t in
        let counter = KeystrokeCounter()
        t.expect(counter.shouldCount(.keyDown(isAutoRepeat: false)))
    },
    TC("auto-repeat keyDown counts") { t in
        let counter = KeystrokeCounter()
        t.expect(counter.shouldCount(.keyDown(isAutoRepeat: true)))
    },
    TC("modifier down transition counts once") { t in
        let counter = KeystrokeCounter()
        t.expect(counter.shouldCount(.flagsChanged(rawFlags: shiftBit)), "shift down should count")
        t.expect(!counter.shouldCount(.flagsChanged(rawFlags: shiftBit)), "repeated same flags must not double count")
    },
    TC("modifier release does not count") { t in
        let counter = KeystrokeCounter()
        _ = counter.shouldCount(.flagsChanged(rawFlags: commandBit))
        t.expect(!counter.shouldCount(.flagsChanged(rawFlags: 0)), "release must not count")
    },
    TC("second modifier while first held counts") { t in
        let counter = KeystrokeCounter()
        t.expect(counter.shouldCount(.flagsChanged(rawFlags: commandBit)))
        t.expect(counter.shouldCount(.flagsChanged(rawFlags: commandBit | shiftBit)), "shift added while cmd held")
        t.expect(!counter.shouldCount(.flagsChanged(rawFlags: commandBit)), "shift released")
        t.expect(!counter.shouldCount(.flagsChanged(rawFlags: 0)), "cmd released")
    },
    TC("caps lock counts on every toggle") { t in
        let counter = KeystrokeCounter()
        t.expect(counter.shouldCount(.flagsChanged(rawFlags: capsBit)), "caps on")
        t.expect(counter.shouldCount(.flagsChanged(rawFlags: 0)), "caps off is a second physical press")
    },
    TC("fn flag alone never counts (avoids arrow-key double count)") { t in
        let counter = KeystrokeCounter()
        t.expect(!counter.shouldCount(.flagsChanged(rawFlags: fnBit)), "fn set")
        t.expect(!counter.shouldCount(.flagsChanged(rawFlags: 0)), "fn cleared")
    },
    TC("control and option transitions count") { t in
        let counter = KeystrokeCounter()
        t.expect(counter.shouldCount(.flagsChanged(rawFlags: controlBit)))
        t.expect(counter.shouldCount(.flagsChanged(rawFlags: controlBit | optionBit)))
    },
]

let inputTrackerTests: [TC] = [
    TC("counts only while a source is active") { t in
        var now: Int64 = 1_700_000_000
        let tracker = InputTracker(clock: { now })
        tracker.handle(.keyDown(isAutoRepeat: false)) // no source yet
        tracker.setActiveSource(7)
        tracker.handle(.keyDown(isAutoRepeat: false))
        tracker.handle(.keyDown(isAutoRepeat: false))
        tracker.setActiveSource(nil)
        tracker.handle(.keyDown(isAutoRepeat: false)) // untracked again
        now += 1
        let drained = tracker.drain()
        t.expectEqual(drained.values.reduce(0, +), 2)
        t.expect(drained.keys.allSatisfy { $0.sourceID == 7 })
    },
    TC("paused state counts nothing but keeps modifier state") { t in
        let tracker = InputTracker(clock: { 1_700_000_000 })
        tracker.setActiveSource(1)
        tracker.setPaused(true)
        tracker.handle(.flagsChanged(rawFlags: shiftBit)) // shift pressed during pause
        tracker.handle(.keyDown(isAutoRepeat: false))
        t.expect(tracker.drain().isEmpty, "nothing counted while paused")
        tracker.setPaused(false)
        // Shift still held from during the pause: same flags again must not count.
        tracker.handle(.flagsChanged(rawFlags: shiftBit))
        t.expect(tracker.drain().isEmpty, "held modifier must not count after resume")
    },
    TC("source switch attributes counts to the right source") { t in
        let tracker = InputTracker(clock: { 1_700_000_000 })
        tracker.setActiveSource(1)
        tracker.handle(.keyDown(isAutoRepeat: false))
        tracker.setActiveSource(2)
        tracker.handle(.keyDown(isAutoRepeat: false))
        tracker.handle(.keyDown(isAutoRepeat: false))
        let totals = tracker.pendingTotalsBySource()
        t.expectEqual(totals[1], 1)
        t.expectEqual(totals[2], 2)
    },
    TC("events land in one-minute buckets") { t in
        var now: Int64 = 1_700_000_000 // not minute aligned: 1_700_000_000 % 60 == 20
        let tracker = InputTracker(clock: { now })
        tracker.setActiveSource(5)
        tracker.handle(.keyDown(isAutoRepeat: false))
        now += 60
        tracker.handle(.keyDown(isAutoRepeat: false))
        let drained = tracker.drain()
        t.expectEqual(drained.count, 2, "two distinct minute buckets")
        for key in drained.keys {
            t.expectEqual(key.minuteStart % 60, 0, "bucket start must be minute aligned")
        }
    },
    TC("drain empties pending counts") { t in
        let tracker = InputTracker(clock: { 1_700_000_000 })
        tracker.setActiveSource(1)
        tracker.handle(.keyDown(isAutoRepeat: false))
        t.expectEqual(tracker.drain().values.reduce(0, +), 1)
        t.expect(tracker.drain().isEmpty, "second drain is empty")
    },
    TC("requeue merges failed-flush counts with new keystrokes") { t in
        let tracker = InputTracker(clock: { 1_700_000_000 })
        tracker.setActiveSource(1)
        tracker.handle(.keyDown(isAutoRepeat: false))
        let drained = tracker.drain()
        tracker.handle(.keyDown(isAutoRepeat: false)) // typed while the write was failing
        tracker.requeue(drained)
        t.expectEqual(tracker.drain().values.reduce(0, +), 2, "requeue must merge, not replace")
    },
]
